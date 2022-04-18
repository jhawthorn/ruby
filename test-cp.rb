require "objspace"

def argh
  ObjectSpace.reachable_objects_from(Foo.instance_method(:initialize)).each do |obj|
    if obj.is_a?(ObjectSpace::InternalObjectWrapper)
      if obj.type == "ment"
        ObjectSpace.reachable_objects_from(obj).each do |obj2|
          if obj2.is_a?(ObjectSpace::InternalObjectWrapper)
            if obj2.type == "iseq"
              p ObjectSpace.reachable_objects_from(obj2).find_all(&:shape?).map(&:shape_id)
            end
          end
        end
      end
    end
  end
end

class Foo
  def initialize
    @foo = 123
  end
end

puts "BEFORE"
argh
foo = Foo.new
foo = Foo.new
foo = Foo.new
foo = Foo.new
puts "AFTER"
argh
exit

class A
  def initialize
    @a = 1
  end
end

class B
  def a= x
  end
end

def set_a(recv, val)
  recv.a = val # have inline cache here
end

loop do
  set_a(A.new, 123) # set referece
  set_a(B.new, 123) # set new reference
  GC.start
end
