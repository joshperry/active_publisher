module ActivePublisher
  module Async
    module InMemoryAdapter
      class AsyncQueue
        include ::ActivePublisher::Logging

        attr_accessor :drop_messages_when_queue_full,
          :max_queue_size,
          :supervisor_interval

        attr_reader :consumer, :queue, :supervisor

        def initialize(drop_messages_when_queue_full, max_queue_size, supervisor_interval)
          @drop_messages_when_queue_full = drop_messages_when_queue_full
          @max_queue_size = max_queue_size
          @supervisor_interval = supervisor_interval
          @queue = ::MultiOpQueue::Queue.new
          create_and_supervise_consumer!
        end

        def push(message)
          # default of 1_000_000 messages
          if queue.size > max_queue_size
            # Drop messages if the queue is full and we were configured to do so
            return if drop_messages_when_queue_full

            # By default we will raise an error to push the responsibility onto the caller
            fail ::ActivePublisher::Async::InMemoryAdapter::UnableToPersistMessageError, "Queue is full, messages will be dropped."
          end

          queue.push(message)
        end

        def size
          # Requests might be in flight (out of the queue, but not yet published), so taking the max should be
          # good enough to make sure we're honest about the actual queue size.
          return queue.size if consumer.nil?
          [queue.size, consumer.sampled_queue_size].max
        end

        private

        def create_and_supervise_consumer!
          @consumer = ::ActivePublisher::Async::InMemoryAdapter::ConsumerThread.new(queue)
          @supervisor = ::Thread.new do
            loop do
              unless consumer.alive?
                consumer.kill
                @consumer = ::ActivePublisher::Async::InMemoryAdapter::ConsumerThread.new(queue)
              end

              # Pause before checking the consumer again.
              sleep supervisor_interval
            end
          end
        end
      end

    end
  end
end