# frozen_string_literal: false
require 'envutil'

class TestThreadInstrumentation < Test::Unit::TestCase
  def setup
    pend("No windows support") if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM

    require '-test-/thread/instrumentation'

    Thread.list.each do |thread|
      if thread != Thread.current
        thread.kill
        thread.join rescue nil
      end
    end
    assert_equal [Thread.current], Thread.list

    Bug::ThreadInstrumentation.register_callback
  end

  def teardown
    return if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM
    Bug::ThreadInstrumentation.unregister_callback
  end

  THREADS_COUNT = 3

  def test_single_thread_timeline
    thread = Thread.new { 1 + 1 }
    thread.join
    full_timeline = Bug::ThreadInstrumentation.unregister_callback
    assert_equal %i(started ready resumed exited), timeline_for(thread, full_timeline)
  ensure
    thread&.kill
  end

  def test_muti_thread_timeline
    threads = threaded_cpu_work
    fib(20)
    assert_equal [false] * THREADS_COUNT, threads.map(&:status)
    full_timeline = Bug::ThreadInstrumentation.unregister_callback
    threads.each do |thread|
      timeline = timeline_for(thread, full_timeline)
      assert_consistent_timeline(timeline)
    end

    timeline = timeline_for(Thread.current, full_timeline)
    assert_consistent_timeline(timeline)
  ensure
    threads&.each(&:kill)
  end

  def test_join_suspends # Bug #18900
    other_thread = Thread.new { sleep 0.3 }
    thread = Thread.new { other_thread.join }
    thread.join

    full_timeline = Bug::ThreadInstrumentation.unregister_callback
    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    assert_equal %i(started ready resumed suspended ready resumed exited), timeline
  ensure
    other_thread&.kill
    thread&.kill
  end

  def test_io_release_gvl
    r, w = IO.pipe
    thread = Thread.new do
      w.write("Hello\n")
    end
    thread.join
    full_timeline = Bug::ThreadInstrumentation.unregister_callback
    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    assert_equal %i(started ready resumed suspended ready resumed exited), timeline
  ensure
    r&.close
    w&.close
  end

  def test_queue_releases_gvl
    queue1 = Queue.new
    queue2 = Queue.new

    thread = Thread.new do
      queue1 << true
      queue2.pop
    end

    queue1.pop
    queue2 << true
    thread.join

    full_timeline = Bug::ThreadInstrumentation.unregister_callback
    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    #assert_equal %i(started ready resumed suspended ready resumed exited), timeline
  end

  def test_thread_blocked_forever
    mutex = Mutex.new
    mutex.lock

    thread = Thread.new do
      mutex.lock
    end
    10.times { Thread.pass }
    sleep 0.1

    full_timeline = Bug::ThreadInstrumentation.unregister_callback
    p thread

    mutex.unlock
    thread.join

    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    assert_equal %i(started ready resumed suspended), timeline
  end

  def test_thread_instrumentation_fork_safe
    skip "No fork()" unless Process.respond_to?(:fork)

    thread_statuses = full_timeline = nil
    IO.popen("-") do |read_pipe|
      if read_pipe
        thread_statuses = Marshal.load(read_pipe)
        full_timeline = Marshal.load(read_pipe)
      else
        threads = threaded_cpu_work
        Marshal.dump(threads.map(&:status), STDOUT)
        full_timeline = Bug::ThreadInstrumentation.unregister_callback.map { |t, e| [t.to_s, e ] }
        Marshal.dump(full_timeline, STDOUT)
      end
    end
    assert_predicate $?, :success?

    assert_equal [false] * THREADS_COUNT, thread_statuses
    thread_names = full_timeline.map(&:first).uniq
    thread_names.each do |thread_name|
      assert_consistent_timeline(timeline_for(thread_name, full_timeline))
    end
  end

  def test_thread_instrumentation_unregister
    Bug::ThreadInstrumentation.unregister_callback
    assert Bug::ThreadInstrumentation::register_and_unregister_callbacks
  end

  private

  def assert_consistent_timeline(events)
    previous_event = nil
    events.each do |event|
      refute_equal :exited, previous_event, "`exited` must be the final event: #{events.inspect}"
      case event
      when :started
        assert_nil previous_event, "`started` must be the first event: #{events.inspect}"
      when :ready
        unless previous_event.nil?
          assert %i(started suspended).include?(previous_event), "`ready` must be preceded by `started` or `suspended`: #{events.inspect}"
        end
      when :resumed
        unless previous_event.nil?
          assert_equal :ready, previous_event, "`resumed` must be preceded by `ready`: #{events.inspect}"
        end
      when :suspended
        unless previous_event.nil?
          assert_equal :resumed, previous_event, "`suspended` must be preceded by `resumed`: #{events.inspect}"
        end
      when :exited
        unless previous_event.nil?
          assert_equal :resumed, previous_event, "`exited` must be preceded by `suspended`: #{events.inspect}"
        end
      end
      previous_event = event
    end
  end

  def timeline_for(thread, timeline)
    timeline.select { |t, _| t == thread }.map(&:last)
  end

  def fib(n = 20)
    return n if n <= 1
    fib(n-1) + fib(n-2)
  end

  def threaded_cpu_work(size = 20)
    THREADS_COUNT.times.map { Thread.new { fib(size) } }.each(&:join)
  end
end
