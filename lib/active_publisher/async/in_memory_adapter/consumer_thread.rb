module ActivePublisher
  module Async
    module InMemoryAdapter
      class ConsumerThread
        attr_reader :thread, :queue, :sampled_queue_size, :heartbeats

        if ::RUBY_PLATFORM == "java"
          NETWORK_ERRORS = [::MarchHare::Exception, ::Java::ComRabbitmqClient::AlreadyClosedException, ::Java::JavaIo::IOException].freeze
        else
          NETWORK_ERRORS = [::Bunny::Exception, ::Timeout::Error, ::IOError].freeze
        end

        def initialize(listen_queue)
          @queue = listen_queue
          @sampled_queue_size = queue.size
          @heartbeats = []
          start_thread
        end

        def alive?
          @thread && @thread.alive?
        end

        def kill
          @thread.kill if @thread
          @thread = nil
        end

        private

        def await_network_reconnect
          if defined?(ActivePublisher::RabbitConnection)
            sleep ::ActivePublisher::RabbitConnection::NETWORK_RECOVERY_INTERVAL
          else
            sleep 0.1
          end
        end

        def make_channel
          channel = ::ActivePublisher::Connection.connection.create_channel
          channel.confirm_select if ::ActivePublisher.configuration.publisher_confirms
          channel
        end

        def send_heartbeat
          @heartbeats << :hello
        end

        def start_thread
          return if alive?
          @thread = ::Thread.new do
            loop do
              # Sample the queue size so we don't shutdown when messages are in flight.
              @sampled_queue_size = queue.size
              current_messages = queue.pop_up_to(50)

              begin
                @channel ||= make_channel

                # Only open a single connection for each group of messages to an exchange
                current_messages.group_by(&:exchange_name).each do |exchange_name, messages|
                  begin
                    current_messages -= messages
                    publish_all(@channel, exchange_name, messages)
                  ensure
                    current_messages.concat(messages)
                  end
                end
              rescue *NETWORK_ERRORS
                # Sleep because connection is down
                await_network_reconnect

                # Requeue and try again.
                queue.concat(current_messages)
              rescue => unknown_error
                ::ActivePublisher.configuration.error_handler.call(unknown_error, {:number_of_messages => current_messages.size})
                current_messages.each do |message|
                  # Degrade to single message publish ... or at least attempt to
                  begin
                    ::ActivePublisher.publish(message.route, message.payload, message.exchange_name, message.options)
                  rescue => individual_error
                    ::ActivePublisher.configuration.error_handler.call(individual_error, {:route => message.route, :payload => message.payload, :exchange_name => message.exchange_name, :options => message.options})
                  end
                end

                # TODO: Find a way to bubble this out of the thread for logging purposes.
                # Reraise the error out of the publisher loop. The Supervisor will restart the consumer.
                raise unknown_error
              end

              send_heartbeat
            end
          end
        end

        def publish_all(channel, exchange_name, messages)
          ::ActiveSupport::Notifications.instrument "message_published.active_publisher", :message_count => messages.size do
            exchange = channel.topic(exchange_name)
            potentially_retry = []
            loop do
              break if messages.empty?
              message = messages.shift

              fail ActivePublisher::UnknownMessageClassError, "bulk publish messages must be ActivePublisher::Message" unless message.is_a?(ActivePublisher::Message)
              fail ActivePublisher::ExchangeMismatchError, "bulk publish messages must match publish_all exchange_name" if message.exchange_name != exchange_name

              begin
                options = ::ActivePublisher.publishing_options(message.route, message.options || {})
                exchange.publish(message.payload, options)
                potentially_retry << message
              rescue
                messages << message
                raise
              end
            end
            wait_for_confirms(channel, messages, potentially_retry)
          end
        end

        def wait_for_confirms(channel, messages, potentially_retry)
          return true unless channel.using_publisher_confirms?
          if channel.method(:wait_for_confirms).arity > 0
            channel.wait_for_confirms(::ActivePublisher.configuration.publisher_confirms_timeout)
          else
            channel.wait_for_confirms
          end
        rescue
          messages.concat(potentially_retry)
          raise
        end
      end
    end
  end
end
