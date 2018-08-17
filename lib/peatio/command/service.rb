# frozen_string_literal: true

module Peatio::Command::Service
  class Start < Peatio::Command::Base
    class Ranger < Peatio::Command::Base
      def execute
        ::Peatio::Ranger.run!
      end
    end

    class UpstreamBinance < Peatio::Command::Base
      option(
        ["-m", "--market"], "MARKET...",
        "markets to listen",
        multivalued: true,
        required: true,
      )

      option(
        ["--dump-interval"], "INTERVAL",
        "interval in seconds for dumping orderbook",
        default: 5,
      ) { |v| Integer(v) }

      def execute
        EM.run {
          orderbooks, trader = ::Peatio::Upstream::Binance.run!(
            markets: market_list,
          )

          trade = trader.submit_order(timeout: 10, order: {
                                        symbol: "ETHBTC",
                                        type: "LIMIT",
                                        side: "BUY",
                                        quantity: 100,
                                        price: 0.4597,
                                      })

          trade.on :error do |request|
            puts request.response
            puts request.response_header.status
          end

          logger = Peatio::Upstream::Binance.logger

          EM::PeriodicTimer.new(dump_interval) do
            orderbooks.each do |symbol, orderbook|
              asks, bids = orderbook.depth(5)

              asks.each do |(price, volume)|
                logger.info "[#{symbol}] {orderbook} ASK #{price} #{volume}"
              end

              bids.each do |(price, volume)|
                logger.info "[#{symbol}] {orderbook} BID #{price} #{volume}"
              end
            end
          end
        }
      end
    end

    subcommand "ranger", "Start ranger process", Ranger
    subcommand "upstream", "Start upstream binance process", UpstreamBinance
  end

  class Root < Peatio::Command::Base
    subcommand "start", "Start a service", Start
  end
end
