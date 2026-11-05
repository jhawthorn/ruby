# frozen_string_literal: true
#
# Generate builtin_aot.inc: C code for every builtin ISEQ, compiled at build
# time from the instruction bodies in insns.def.
#
#   miniruby tool/mk_builtin_aot.rb [--cross=yes] > builtin_aot.inc
#
# Must run in the miniruby that also writes builtin_binary.rbbin so that the
# ISEQs here are the ones ruby loads; see doc/jit/builtin_aot.md. Each
# function emits, for each instruction, what vm.inc would run for it, with the
# dispatch gone and the operands known. The frame is always left exactly as
# the interpreter would leave it, so the interpreter can take over at any
# instruction boundary.

require_relative 'ruby_vm/models/instructions'
require_relative 'ruby_vm/models/typemap'

module BuiltinAOT
  INSNS = RubyVM::Instructions.each_with_object({}) { |i, h| h[i.name] = i }
  SEND_WITHOUT_BLOCK = INSNS.fetch('opt_send_without_block')

  # Integer operands to_a reports verbatim; bake them in as constants.
  CONST_TYPES = %w[lindex_t rb_num_t]

  # ISEQ types that get compiled; the rest run once or are entered through
  # the exception handler, which doesn't enter compiled code.
  COMPILED_TYPES = %i[method block]

  class Unsupported < StandardError; end

  # Builtin code may assume that methods of builtin classes are the builtin
  # definitions: Box keeps user redefinitions out of the box builtins run in.
  # The interpreter checks that with BASIC_OP_UNREDEFINED_P inside the
  # vm_opt_* helpers, which compiled code shares with it. So compiled code
  # gets its own copies of those helpers (aot_vm_opt_plus, ...), compiled
  # with the check defined to be true.
  module AssumeCore
    SRC = File.read(File.expand_path('../vm_insnhelper.c', __dir__))
    FUNCS = {}
    SRC.scan(/^(static[^\n;{]*)\n(\w+)\(([^{;]*?)\)\n\{\n(.*?)^\}\n/m) do |ret, name, args, body|
      FUNCS[name] = [ret, args, body]
    end

    # Helpers that check for redefinition, directly or through another one.
    # Only the instruction helpers, not the call machinery.
    CANDIDATES = FUNCS.keys.grep(/\A(vm_opt_|opt_|vm_case_dispatch\z)/)
    CHECKS = /\b\w*_UNREDEFINED_P\(|\bCMP_OPTIMIZABLE\(/
    NAMES = CANDIDATES.select { |n| FUNCS[n][2].match?(CHECKS) }
    loop do
      added = (CANDIDATES - NAMES).select { |n| NAMES.any? { |c| FUNCS[n][2].match?(/\b#{c}\(/) } }
      break if added.empty?
      NAMES.concat(added)
    end
    NAMES.freeze
    CALL = /\b(#{NAMES.join('|')})\(/

    def self.rename(text)
      text.gsub(CALL) { "aot_#{$1}(" }
    end

    # The copies the generated code calls, and the ones they call.
    def self.copies(code)
      used = code.scan(/\baot_(\w+)\(/).flatten.select { |n| NAMES.include?(n) }.uniq
      queue = used.dup
      until queue.empty?
        FUNCS[queue.shift][2].scan(CALL).flatten.each do |n|
          next if used.include?(n)
          used << n
          queue << n
        end
      end
      used.sort!
      out = +"#pragma push_macro(\"BASIC_OP_UNREDEFINED_P\")\n"
      out << "#undef BASIC_OP_UNREDEFINED_P\n"
      out << "#define BASIC_OP_UNREDEFINED_P(op, klass) ((void)(op), (void)(klass), 1)\n"
      # vm_insnhelper.c's shorthands, #undef'd at its end
      SRC.scan(/^#define ((?:OP|EQ)_UNREDEFINED_P\b.*)$/) { out << "#define #{$1}\n" }
      out << "\n"
      used.each do |n|
        ret, args, = FUNCS[n]
        out << "#{ret} aot_#{n}(#{args});\n"
      end
      out << "\n"
      used.each do |n|
        ret, args, body = FUNCS[n]
        out << "#{ret}\naot_#{n}(#{args})\n{\n#{rename(body)}}\n\n"
      end
      out
    end

    def self.close
      "#undef EQ_UNREDEFINED_P\n#undef OP_UNREDEFINED_P\n#pragma pop_macro(\"BASIC_OP_UNREDEFINED_P\")\n"
    end
  end

  class ISeqCompiler
    attr_reader :name

    def initialize(name, iseq)
      @name = name
      @iseq = iseq
      ary = iseq.to_a
      @type = ary[9]
      @label = ary[5]
      @path = ary[6]
      @lineno = ary[8]
      # Methods with optional parameters start at an opt_table entry.
      @starts = (ary[11][:opt] || []).map { |l| label_pos(l) }
      @insns = []
      pos = 0
      ary[13].each do |elem|
        case elem
        when Array
          insn = INSNS.fetch(elem[0].to_s)
          @insns << [pos, insn, elem[1..]]
          pos += insn.width
        when Symbol
          if (m = /\Alabel_(\d+)\z/.match(elem)) && m[1].to_i != pos
            raise "#{@label}: #{elem} at #{pos}"
          end
        end
      end
      @size = pos
    end

    attr_reader :size

    # Entering compiled code, and resuming it after a call into Ruby, cost
    # about as much as dispatching a few instructions. So only compile ISEQs
    # that are long, or that loop over enough instructions per such call
    # (Integer#times: 10 per yield; Kernel#loop, 3, is faster interpreted).
    MIN_INSNS = 20
    MIN_LOOP_INSNS_PER_CALL = 6

    def compiled?
      return false unless COMPILED_TYPES.include?(@type)
      return true if @insns.size >= MIN_INSNS
      @insns.each do |pos, insn, opes|
        insn.operands.each_with_index do |o, i|
          next unless o[:type] == 'OFFSET' && (start = label_pos(opes[i])) <= pos
          body = @insns.select { |p, _, _| p >= start && p <= pos }
          calls = body.count { |_, i2, _| i2.expr.expr.include?('JIT_EXEC(') }
          return true if body.size >= MIN_LOOP_INSNS_PER_CALL * [calls, 1].max
        end
      end
      false
    end

    def label_pos(sym)
      Integer(sym.to_s.delete_prefix('label_'))
    end

    def generate
      @labels = {}         # pos => true, positions that need a C label
      @resume = []         # positions where a suspended call resumes
      out = +''
      body = +''
      @insns.each_with_index do |(pos, insn, opes), idx|
        nxt = pos + insn.width
        body << compile_insn(pos, nxt, insn, opes, @insns[idx + 1])
      end

      out << "/* #{@label} (#{@path}:#{@lineno}, #{@type}) */\n"
      out << "static VALUE\n#{name}(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, bool aot_resume)\n{\n"
      out << "    const VALUE *const pc0 = ISEQ_BODY(reg_cfp->_iseq)->iseq_encoded;\n"
      @starts.each { |pos| @labels[pos] = true }
      out << "    if (aot_resume) {\n"
      out << "        switch (GET_PC() - pc0) {\n"
      @resume.uniq.sort.each { |pos| out << "          case #{pos}: goto label_#{pos};\n" }
      out << "          default: return Qundef;\n"
      out << "        }\n"
      out << "    }\n"
      unless @starts.reject(&:zero?).empty?
        out << "    switch (GET_PC() - pc0) {\n"
        @starts.uniq.each { |pos| out << "      case #{pos}: goto label_#{pos};\n" }
        out << "      default: return Qundef;\n"
        out << "    }\n"
      end
      out << body
      out << "    rb_bug(\"#{name}: fell off the end\");\n"
      out << "}\n"
      # Emit labels only where something jumps, so there are no unused ones.
      out.gsub!(/^  LABEL (\d+):\n/) { @labels[$1.to_i] ? "  label_#{$1}:\n" : '' }
      out << "\n"
      out
    end

    private

    def target(nxt, offset_label)
      pos = label_pos(offset_label)
      @labels[pos] = true
      pos
    end

    def compile_insn(pos, nxt, insn, opes, following)
      out = +"  LABEL #{pos}:\n"
      case insn.name
      when 'leave'
        out << <<~C.gsub(/^/, '    ')
          /* #{pos} leave */
          if (aot_resume) { SET_PC(pc0 + #{pos}); return Qundef; }
          {
              VALUE val = TOPN(0);
              SET_PC(pc0 + #{nxt});
              POPN(1);
              vm_pop_frame(ec, reg_cfp, GET_EP());
              return val;
          }
        C
        return out
      when 'opt_invokebuiltin_delegate_leave'
        raise Unsupported, "#{insn.name} not followed by leave" unless following && following[1].name == 'leave'
        out << <<~C.gsub(/^/, '    ')
          /* #{pos} opt_invokebuiltin_delegate_leave */
          {
              SET_PC(pc0 + #{nxt});
              VALUE val = vm_invoke_builtin_delegate(ec, reg_cfp, (RB_BUILTIN)pc0[#{pos + 1}], (unsigned int)#{Integer(opes[1])});
              if (aot_resume) { PUSH(val); return Qundef; }
              vm_pop_frame(ec, reg_cfp, GET_EP());
              return val;
          }
        C
        return out
      when 'throw'
        return out << side_exit(pos, insn)
      end

      begin
        out << emit(pos, nxt, insn, opes)
      rescue Unsupported => e
        out << side_exit(pos, insn, e.message)
      end
      out
    end

    def side_exit(pos, insn, why = nil)
      "    /* #{pos} #{insn.name}#{why && ": #{why}"} */\n    SET_PC(pc0 + #{pos}); return Qundef;\n"
    end

    # The instruction as vm.inc's _insn_entry.erb would run it.
    def emit(pos, nxt, insn, opes, simple_of: nil)
      expr = AssumeCore.rename(insn.expr.expr.dup)
      decls = +''
      insn.preamble.each { |konst| decls << "    #{konst.expr.strip}\n" }
      insn.operands.each_with_index do |ope, i|
        decls << "    #{ope[:decl]} = #{operand(pos, nxt, ope, opes[i], i)};\n"
      end

      jumps = []
      calls_ruby = expr.include?('JIT_EXEC(')
      simple = expr.include?('CALL_SIMPLE_METHOD()')
      if simple
        # CALL_SIMPLE_METHOD backs pc up by the width of
        # opt_send_without_block and dispatches to it, so it reads its
        # operands from the end of this instruction's (opt_neq passes the
        # second of its two call data that way).
        send_pos = nxt - SEND_WITHOUT_BLOCK.width
        send_opes = opes[(send_pos - pos)..]
        unless simple_of.nil? && send_pos >= pos &&
               insn.operands[(send_pos - pos)..] == SEND_WITHOUT_BLOCK.operands
          raise Unsupported, 'CALL_SIMPLE_METHOD with different operands'
        end
      end

      expr.gsub!(/\bJIT_EXEC\(ec, val\);/) { 'AOT_EXEC_PUSHED(val);' }
      expr.gsub!(/\bRESTORE_REGS\(\);\s*NEXT_INSN\(\);/) { 'return Qundef;' }
      expr.gsub!(/\bCALL_SIMPLE_METHOD\(\);/) { "goto simple_#{pos};" }
      expr.gsub!(/\bINSN_LABEL\((\w+)\)/) { "INSN_LABEL_#{$1}_#{pos}" }
      expr.gsub!(/\bJUMP\(([^)]+)\);/) do
        dst = $1
        jumps << dst
        "(aot_jumped = true, aot_jump_dst = (#{dst}));"
      end
      %w[RESTORE_REGS NEXT_INSN THROW_EXCEPTION DISPATCH_ORIGINAL_INSN GET_CURRENT_INSN ADD_PC GET_OPERAND].each do |m|
        raise Unsupported, m if expr.match?(/\b#{m}\b/)
      end

      out = +"    /* #{pos} #{insn.name} */\n    {\n"
      out << decls
      out << "#   define INSN_ATTR(x) #{insn.call_attribute(' ## x ## ')}\n"
      out << "        const bool MAYBE_UNUSED(leaf) = INSN_ATTR(leaf);\n"
      insn.pops.reverse_each.with_index.reverse_each do |pop, i|
        out << "        #{pop[:decl]} = #{insn.cast_from_VALUE(pop, "TOPN(#{i})")};\n"
      end
      insn.rets.each do |ret|
        next if insn.has_ope?(ret) || insn.has_pop?(ret)
        out << "        #{ret[:decl]};\n"
      end
      out << "        bool aot_jumped = false; OFFSET aot_jump_dst = 0;\n" unless jumps.empty?
      # Leaf instructions can't raise or call out, so nothing reads pc while
      # they run; every exit sets it.
      out << "        if (!INSN_ATTR(leaf)) SET_PC(pc0 + #{nxt});\n"
      out << "        POPN(INSN_ATTR(popn));\n" if insn.handles_sp?
      out << "#   define NAME_OF_CURRENT_INSN #{insn.name}\n"
      out << expr.gsub(/^/, '        ') << "\n"
      out << "#   undef NAME_OF_CURRENT_INSN\n"
      if insn.handles_sp?
        insn.rets.reverse_each { |ret| out << "        PUSH(#{insn.cast_to_VALUE(ret)});\n" }
      else
        out << "        INC_SP(INSN_ATTR(sp_inc));\n"
        insn.rets.reverse_each.with_index do |ret, i|
          out << "        TOPN(#{i}) = #{insn.cast_to_VALUE(ret)};\n"
        end
      end
      unless jumps.empty?
        out << "        if (aot_jumped) {\n"
        out << "            switch (aot_jump_dst) {\n"
        jump_targets(pos, nxt, insn, opes).each do |t|
          out << "              case #{t - nxt}: goto label_#{t};\n"
        end
        out << "              default: SET_PC(pc0 + #{nxt} + aot_jump_dst); return Qundef;\n"
        out << "            }\n"
        out << "        }\n"
      end
      out << "        if (!INSN_ATTR(leaf)) AOT_TRACE_CHECK();\n"
      out << "#   undef INSN_ATTR\n"
      out << "    }\n"

      if calls_ruby
        @resume << nxt
        @labels[nxt] = true
      end
      if simple
        @resume << nxt
        @labels[nxt] = true
        out << "    if (0) {\n      simple_#{pos}:\n"
        out << emit(send_pos, nxt, SEND_WITHOUT_BLOCK, send_opes, simple_of: insn).gsub(/^/, '    ')
        out << "        goto label_#{nxt};\n    }\n"
      end
      out
    end

    def jump_targets(pos, nxt, insn, opes)
      targets = []
      insn.operands.each_with_index do |ope, i|
        targets << target(nxt, opes[i]) if ope[:type] == 'OFFSET'
        if ope[:type] == 'CDHASH'
          opes[i].each_slice(2) { |_, l| targets << target(nxt, l) }
        end
      end
      raise Unsupported, 'JUMP without known targets' if targets.empty?
      targets.uniq
    end

    def operand(pos, nxt, ope, value, i)
      type = ope[:type]
      if type == 'OFFSET'
        "(OFFSET)#{label_pos(value) - nxt}"
      elsif CONST_TYPES.include?(type) && value.is_a?(Integer)
        "(#{type})#{value}"
      else
        "(#{type})pc0[#{pos + 1 + i}]"
      end
    end
  end

  def self.generate(io)
    unless RubyVM.respond_to?(:each_builtin) && RubyVM.respond_to?(:builtin_aot_iseqs) && !ARGV.include?('--builtin-binary=no')
      io.puts '// no builtin AOT (no builtin binary, e.g. cross build)'
      io.puts 'static const struct rb_aot_feature rb_aot_features[] = { { NULL, NULL, 0 } };'
      return
    end

    features = []
    io.puts '// -*- c -*-'
    io.puts '// DO NOT MODIFY THIS FILE DIRECTLY.'
    io.puts "// auto-generated file by #{File.basename(__FILE__)}"
    io.puts
    code = +''
    RubyVM.each_builtin do |feature, top|
      entries = []
      RubyVM.builtin_aot_iseqs(top).each_with_index do |iseq, n|
        c = ISeqCompiler.new("aot_#{feature}_#{n}", iseq)
        if c.compiled?
          code << c.generate
          entries << "{ #{c.size}, #{c.name} }"
        else
          entries << "{ #{c.size}, NULL }"
        end
      end
      code << "static const struct rb_aot_iseq aot_#{feature}_table[] = {\n"
      entries.each { |e| code << "    #{e},\n" }
      code << "};\n\n"
      features << [feature, entries.size]
    end
    io.write AssumeCore.copies(code)
    io.write code
    io.write AssumeCore.close
    io.puts 'static const struct rb_aot_feature rb_aot_features[] = {'
    features.each { |f, n| io.puts "    { #{f.dump}, aot_#{f}_table, #{n} }," }
    io.puts '    { NULL, NULL, 0 },'
    io.puts '};'
  end
end

out = ARGV.find { _1.start_with?('-o') }&.delete_prefix('-o')
if out
  File.open(out, 'w') { |f| BuiltinAOT.generate(f) }
else
  BuiltinAOT.generate($stdout)
end
