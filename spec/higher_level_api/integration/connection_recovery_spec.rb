require "spec_helper"
require "rabbitmq/http/client"

describe "Connection recovery" do
  let(:connection)  {  }
  let(:http_client) { RabbitMQ::HTTP::Client.new("http://127.0.0.1:15672") }

  def close_all_connections!
    http_client.list_connections.each do |conn_info|
      http_client.close_connection(conn_info.name)
    end
  end

  def wait_for_recovery
    sleep 2.0
  end

  def with_open(c = MarchHare.connect(:network_recovery_interval => 0.2), &block)
    begin
      block.call(c)
    ensure
      c.close if c.open?
    end
  end

  def ensure_queue_recovery(ch, q)
    q.purge
    x = ch.default_exchange
    x.publish("msg", :routing_key => q.name)
    sleep 0.2
    expect(q.message_count).to eq(1)
    q.purge
  end

  def ensure_queue_binding_recovery(x, q, routing_key = "")
    q.purge
    x.publish("msg", :routing_key => routing_key)
    sleep 0.2
    expect(q.message_count).to eq(1)
    q.purge
  end

  def ensure_exchange_binding_recovery(ch, source, destination, routing_key = "")
    q  = ch.queue("", :exclusive => true)
    q.bind(destination, :routing_key => routing_key)

    source.publish("msg", :routing_key => routing_key)
    ch.wait_for_confirms
    expect(q.message_count).to eq(1)
    q.delete
  end

  #
  # Examples
  #

  it "reconnects after grace period" do
    with_open do |c|
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(c).to be_open
    end
  end

  it "recovers channel" do
    with_open do |c|
      ch1 = c.create_channel
      ch2 = c.create_channel
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch1).to be_open
      expect(ch2).to be_open
    end
  end

  it "recovers basic.qos prefetch setting" do
    with_open do |c|
      ch = c.create_channel
      ch.prefetch = 11
      expect(ch.prefetch).to eq(11)
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open
      expect(ch.prefetch).to eq(11)
    end
  end


  it "recovers publisher confirms setting" do
    with_open do |c|
      ch = c.create_channel
      ch.confirm_select
      expect(ch).to be_using_publisher_confirms
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open
      expect(ch).to be_using_publisher_confirms
    end
  end

  it "recovers transactionality setting" do
    with_open do |c|
      ch = c.create_channel
      ch.tx_select
      expect(ch).to be_using_tx
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open
      expect(ch).to be_using_tx
    end
  end

  it "recovers client-named queues" do
    with_open do |c|
      ch = c.create_channel
      q  = ch.queue("bunny.tests.recovery.client-named#{rand}")
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open
      ensure_queue_recovery(ch, q)
      q.delete
    end
  end


  it "recovers server-named queues" do
    with_open do |c|
      ch = c.create_channel
      q  = ch.queue("", :exclusive => true)
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open
      ensure_queue_recovery(ch, q)
    end
  end

  it "recovers queue bindings" do
    with_open do |c|
      ch = c.create_channel
      x  = ch.fanout("amq.fanout")
      q  = ch.queue("", :exclusive => true)
      q.bind(x)
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open
      ensure_queue_binding_recovery(x, q)
    end
  end

  it "recovers exchange bindings" do
    with_open do |c|
      ch = c.create_channel
      ch.confirm_select
      x  = ch.fanout("amq.fanout")
      x2 = ch.fanout("bunny.tests.recovery.fanout")
      x2.bind(x)
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open
      ensure_exchange_binding_recovery(ch, x, x2)
    end
  end

  it "recovers consumers" do
    with_open do |c|
      delivered = false

      ch = c.create_channel
      q  = ch.queue("", :exclusive => true)
      q.subscribe do |_, _, _|
        delivered = true
      end
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open

      q.publish("")
      sleep 0.5
      expect(delivered).to eq(true)
    end
  end

  it "recovers all consumers" do
    n = 1024

    with_open do |c|
      ch = c.create_channel
      q  = ch.queue("", :exclusive => true)
      n.times do
        q.subscribe do |_, _, _|
          delivered = true
        end
      end
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open

      expect(q.consumer_count).to eq(n)
    end
  end

  it "recovers all queues" do
    n = 256

    qs = []

    with_open do |c|
      ch = c.create_channel

      n.times do
        qs << ch.queue("", :exclusive => true)
      end
      close_all_connections!
      sleep 0.1
      expect(c).not_to be_open

      wait_for_recovery
      expect(ch).to be_open

      qs.each do |q|
        ch.queue_declare_passive(q.name)
      end
    end
  end
end
