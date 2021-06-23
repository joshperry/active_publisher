#!/usr/bin/env ruby

require "bundler/setup"
require "active_publisher"

payload = (0...1000).map { (65 + rand(26)).chr }.join

::ActivePublisher.configuration.host = 'rabbitmq'
::ActivePublisher.configuration.seconds_to_wait_for_graceful_shutdown = 3600
::ActivePublisher.configuration.publisher_confirms = true

if false
  require "connection_pool"
  require "redis"
  require "active_publisher/async/redis_adapter"

  redis_pool = ::ConnectionPool.new(:size => 10) { ::Redis.new(:host => 'redis') }

  ::ActivePublisher::Configuration.configure_from_yaml_and_cli({})
  ::ActivePublisher::Async.publisher_adapter = ::ActivePublisher::Async::RedisAdapter.new(redis_pool)
else
  ::ActivePublisher::Async.publisher_adapter = ::ActivePublisher::Async::InMemoryAdapter.new('wait'.to_sym, 1000000)
end

(0..1000000).each {|i| ::ActivePublisher.publish_async('messages.testing', payload, 'actions') }

sleep 3600
