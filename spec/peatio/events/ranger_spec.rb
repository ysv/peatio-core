require "em-spec/rspec"
require "bunny-mock"

describe Peatio::Ranger do
  let(:logger) { Peatio::Logger }

  let(:ws_client) {
    ws_connect
  }

  let(:jwt_private_key) {
    OpenSSL::PKey::RSA.generate 2048
  }

  let(:jwt_public_key) {
    jwt_private_key.public_key
  }

  let(:auth) {
    Peatio::Auth::JWTAuthenticator.new(jwt_public_key, jwt_private_key)
  }

  let(:logger) {
    Peatio::Logger.logger
  }

  let(:msg_auth_failed) {
    "{\"error\":{\"message\":\"Authentication failed.\"}}"
  }

  let(:msg_auth_success) {
    "{\"success\":{\"message\":\"Authenticated.\"}}"
  }

  let(:valid_token_payload) {
    payload = {:iat => 1534242281,
               :exp => (Time.now + 3600).to_i,
               :sub => "session",
               :iss => "barong",
               :aud => ["peatio",
                        "barong"],
               :jti => "BEF5617B7B2762DDE61702F5",
               :uid => "IDE8E2280FD1",
               :email => "email@heliostech.fr",
               :role => "admin",
               :level => 4,

               :state => "active"}
  }

  let(:valid_token) {
    auth.encode(valid_token_payload)
  }

  include EM::SpecHelper

  context "invalid json data" do
    before do
      Peatio::MQ::Client.new
      Peatio::MQ::Client.connection = BunnyMock.new.start
      Peatio::MQ::Client.create_channel!
    end

    it "denies access" do
      em {
        ws_server do |socket|
          connection = Peatio::Ranger::Connection.new(auth, socket, logger)
          socket.onopen do |handshake|
            connection.handshake(handshake)
          end
          socket.onmessage do |msg|
            connection.handle(msg)
          end
        end

        EM.add_timer(0.1) do
          ws_client.callback { ws_client.send_msg "garbage" }
          ws_client.disconnect { done }
          ws_client.stream { |msg|
            expect(msg.data).to eq msg_auth_failed
            done
          }
        end
      }
    end
  end

  context "invalid token" do
    before do
      Peatio::MQ::Client.new
      Peatio::MQ::Client.connection = BunnyMock.new.start
      Peatio::MQ::Client.create_channel!
    end

    it "denies access" do
      em {
        ws_server do |socket|
          connection = Peatio::Ranger::Connection.new(auth, socket, logger)
          socket.onopen do |handshake|
            connection.handshake(handshake)
          end
          socket.onmessage do |msg|
            connection.handle(msg)
          end
        end

        EM.add_timer(0.1) do
          ws_client.callback {
            token = auth.encode("").to_json
            auth_msg = {jwt: "Bearer #{token}"}
            ws_client.send_msg auth_msg.to_json
          }
          ws_client.disconnect { done }
          ws_client.stream { |msg|
            expect(msg.data).to eq msg_auth_failed
            done
          }
        end
      }
    end
  end

  context "valid token" do
    before do
      Peatio::MQ::Client.new
      Peatio::MQ::Client.connection = BunnyMock.new.start
      Peatio::MQ::Client.create_channel!
    end

    it "allows access" do
      em {
        ws_server do |socket|
          connection = Peatio::Ranger::Connection.new(auth, socket, logger)

          socket.onopen do |handshake|
            connection.handshake(handshake)
          end

          socket.onmessage do |msg|
            connection.handle(msg)
          end
        end

        EM.add_timer(0.1) do
          ws_client.callback {
            auth_msg = {jwt: "Bearer #{valid_token}"}
            ws_client.send_msg auth_msg.to_json
          }
          ws_client.disconnect { done }
          ws_client.stream { |msg|
            expect(msg.data).to eq msg_auth_success
            done
          }
        end
      }
    end
  end

  context "valid token" do
    before do
      Peatio::MQ::Client.new
      Peatio::MQ::Client.connection = BunnyMock.new.start
      Peatio::MQ::Client.create_channel!

      Peatio::MQ::Events.subscribe!
    end

    it "sends messages that belong to the user and filtered by stream" do
      em {
        ws_server do |socket|
          connection = Peatio::Ranger::Connection.new(auth, socket, logger)

          socket.onopen do |handshake|
            connection.handshake(handshake)
          end

          socket.onmessage do |msg|
            connection.handle(msg)
          end
        end

        EM.add_timer(0.1) do
          ws_client = ws_connect("/?stream=stream_1&stream=stream_2")

          ws_client.callback {
            auth_msg = {jwt: "Bearer #{valid_token}"}

            ws_client.send_msg auth_msg.to_json
          }

          step = 0
          ws_client.stream { |msg|
            step += 1

            case step
            when 1
              expect(msg.data).to eq msg_auth_success

              Peatio::MQ::Events.publish("private", valid_token_payload[:uid], "stream_1", {
                data: "stream_1_user_1",
              })

              Peatio::MQ::Events.publish("private", "SOMEUSER2", "stream_1", {
                data: "stream_1_user_2",
              })

              Peatio::MQ::Events.publish("private", valid_token_payload[:uid], "stream_2", {
                data: "stream_2_user_1",
              })

              Peatio::MQ::Events.publish("private", valid_token_payload[:uid], "stream_3", {
                data: "stream_3_user_1",
              })

              Peatio::MQ::Events.publish("private", valid_token_payload[:uid], "stream_2", {
                data: "stream_2_user_1_message_2",
              })
            when 2
              expect(msg.data).to eq '{"data":"stream_1_user_1"}'
            when 3
              expect(msg.data).to eq '{"data":"stream_2_user_1"}'
            when 4
              expect(msg.data).to eq '{"data":"stream_2_user_1_message_2"}'
              done
            end
          }
        end

        ws_client.disconnect { done }
      }
    end

    it "sends public messages filtered by stream" do
      em {
        ws_server do |socket|
          connection = Peatio::Ranger::Connection.new(auth, socket, logger)

          socket.onopen do |handshake|
            connection.handshake(handshake)
          end

          socket.onmessage do |msg|
            connection.handle(msg)
          end
        end

        EM.add_timer(0.1) do
          ws_client = ws_connect("/?stream=btcusd.order")

          ws_client.callback {
            Peatio::MQ::Events.publish("public", "btcusd", "order", {
              data: "btcusd_order_1",
            })
            Peatio::MQ::Events.publish("public", "btcusd", "order", {
              data: "btcusd_order_2",
            })
            Peatio::MQ::Events.publish("public", "btcusd", "trade", {
              data: "btcusd_trade_2",
            })
            Peatio::MQ::Events.publish("public", "ethusd", "order", {
              data: "ethusd_order_1",
            })
            Peatio::MQ::Events.publish("public", "btcusd", "order", {
              data: "btcusd_order_3",
            })
          }

          step = 0
          ws_client.stream { |msg|
            step += 1

            case step
            when 1
              expect(msg.data).to eq '{"data":"btcusd_order_1"}'
            when 2
              expect(msg.data).to eq '{"data":"btcusd_order_2"}'
            when 3
              expect(msg.data).to eq '{"data":"btcusd_order_3"}'
              done
            end
          }
        end

        ws_client.disconnect { done }
      }
    end
  end
end