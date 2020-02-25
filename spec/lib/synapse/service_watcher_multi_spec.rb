require 'spec_helper'
require 'synapse/service_watcher/multi'
require 'synapse/service_watcher/zookeeper'
require 'synapse/service_watcher/dns'

describe Synapse::ServiceWatcher::MultiWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end

  subject {
    Synapse::ServiceWatcher::MultiWatcher.new(config, mock_synapse)
  }

  let(:discovery) do
    valid_discovery
  end

  let (:zk_discovery) do
    {'method' => 'zookeeper', 'hosts' => 'localhost:2181', 'path' => '/smartstack'}
  end

  let (:dns_discovery) do
    {'method' => 'dns', 'servers' => ['localhost']}
  end

  let(:valid_discovery) do
    {'method' => 'multi',
     'resolver' => {
       'method' => 's3_toggle',
       'default' => 'primary',
     },
     'watchers' => {
       'primary' => zk_discovery,
       'secondary' => dns_discovery,
     },
     'resolver' => {
       'method' => 'fallback',
     }}
  end

  let(:config) do
    {
      'name' => 'test',
      'haproxy' => {},
      'discovery' => discovery,
    }
  end

  let(:new_hosts) do
    [{
      'host' => 'test',
      'port' => 1234,
      'name' => 'i-test',
    }]
  end

  describe '.initialize' do
    subject {
      Synapse::ServiceWatcher::MultiWatcher
    }

    context 'with empty configuration' do
      let(:discovery) do
        {}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with empty watcher configuration' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with undefined watchers' do
      let(:discovery) do
        {'method' => 'muli'}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with wrong method type' do
      let(:discovery) do
        {'method' => 'zookeeper', 'watchers' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with invalid child watcher definition' do
      let(:discovery) {
        {'method' => 'multi', 'watchers' => {
           'secondary' => {
             'method' => 'bogus',
           }
         }}
      }

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with invalid child watcher type' do
      let(:discovery) {
        {'method' => 'multi', 'watchers' => {
           'child' => 'not_a_hash'
         }}
      }

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with undefined resolver' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {
           'child' => zk_discovery
         }}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with empty resolver' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {
           'child' => zk_discovery
         },
        'resolver' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse)
        }.to raise_error ArgumentError
      end
    end

    context 'with valid configuration' do
      let(:discovery) do
        valid_discovery
      end

      it 'creates the requested watchers' do
        expect(Synapse::ServiceWatcher::ZookeeperWatcher)
          .to receive(:new)
          .with({'name' => 'test', 'haproxy' => {}, 'discovery' => zk_discovery},
                  duck_type(:call),
                  mock_synapse)
          .and_call_original
        expect(Synapse::ServiceWatcher::DnsWatcher)
          .to receive(:new)
          .with({'name' => 'test', 'haproxy' => {}, 'discovery' => dns_discovery},
                 duck_type(:call),
                 mock_synapse)
          .and_call_original

        expect {
          subject.new(config, mock_synapse)
        }.not_to raise_error
      end

      it 'sets @watchers to each watcher' do
        multi_watcher = subject.new(config, mock_synapse)
        watchers = multi_watcher.instance_variable_get(:@watchers)

        expect(watchers.has_key?('primary'))
        expect(watchers.has_key?('secondary'))

        expect(watchers['primary']).to be_instance_of(Synapse::ServiceWatcher::ZookeeperWatcher)
        expect(watchers['secondary']).to be_instance_of(Synapse::ServiceWatcher::DnsWatcher)
      end
    end
  end

  describe '.start' do
    it 'starts all child watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:start)
      end

      expect {
        subject.start
      }.not_to raise_error
    end
  end

  describe '.stop' do
    it 'stops all child watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:stop)
      end

      expect {
        subject.stop
      }.not_to raise_error
    end
  end

  describe ".ping?" do
    it 'calls ping? on all watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:ping?).and_return true
      end

      expect {
        subject.ping?
      }.not_to raise_error
    end
  end

  describe "children watchers" do
    describe ".reconfigure!" do
      it "does not call synapse reconfigure" do
        expect(mock_synapse).not_to receive(:reconfigure!)

        watchers = subject.instance_variable_get(:@watchers).values
        watchers.each do |w|
          w.send(:reconfigure!)
        end
      end

      it "notifies multi-watcher" do
        watchers = subject.instance_variable_get(:@watchers).values
        callable = subject.instance_variable_get(:@child_notification_callback)

        expect(callable).to receive(:call).exactly(watchers.length).and_call_original
        watchers.each do |w|
          w.send(:reconfigure!)
        end
      end
    end

    describe "set_backends" do
      it "does not call synapse reconfigure" do
        expect(mock_synapse).not_to receive(:reconfigure!)

        watchers = subject.instance_variable_get(:@watchers).values
        watchers.each do |w|
          w.send(:set_backends, new_hosts)
        end
      end

      it "notifies multi-watcher" do
        watchers = subject.instance_variable_get(:@watchers).values
        callable = subject.instance_variable_get(:@child_notification_callback)

        expect(callable).to receive(:call).exactly(watchers.length).and_call_original
        watchers.each do |w|
          w.send(:reconfigure!)
        end
      end
    end
  end
end
