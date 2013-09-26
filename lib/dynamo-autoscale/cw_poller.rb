module DynamoAutoscale
  class CWPoller < Poller
    include DynamoAutoscale::Logger
    INTERVAL = 5.minutes

    def backdate
      now = Time.now.utc

      @tables.each do |table_name|
        table = DynamoAutoscale.tables[table_name]
        dispatch(table, Metrics.all_metrics(table_name, {
          period:     5.minutes,
          start_time: now - 6.hours,
          end_time:   now,
        }))
      end
    end

    def poll tables, &block
      tables = AWS::DynamoDB.new.tables.to_a.map(&:name) if tables.nil?

      loop do
        # Sleep until the next interval occurrs. This calculation ensures that
        # polling always happens on interval boundaries regardless of how long
        # polling takes.
        sleep_duration = INTERVAL - ((Time.now.to_i + INTERVAL) % INTERVAL)
        logger.debug "[cw_poller] Sleeping for #{sleep_duration} seconds..."
        sleep(sleep_duration)

        logger.debug "[cw_poller] +++ old tables: #{DynamoAutoscale.poller_opts} #{ARGV[0]}"

        tables = DynamoAutoscale.reload_tables(ARGV[0])
        DynamoAutoscale.poller_opts[:tables] = tables
        logger.debug "[cw_poller] +++ new tables: #{DynamoAutoscale.poller_opts}"

        do_poll(tables, &block)
      end
    end

    def do_poll tables, &block
      logger.debug "[cw_poller] Beginning CloudWatch poll..."
      now = Time.now

      tables.each do |table_name|
        # This code will dispatch a message to the listening table that looks
        # like this:
        #
        #   {
        #     :consumed_reads=>{
        #       2013-06-19 12:22:00 UTC=>2.343117697349672
        #     },
        #     :consumed_writes=>{
        #       2013-06-19 12:22:00 UTC=>3.0288461538461537
        #     }
        #   }
        #
        # There may also be :provisioned_reads and :provisioned_writes
        # depending on how the CloudWatch API feels.
        block.call(table_name, Metrics.all_metrics(table_name, {
          period:     5.minutes,
          start_time: now - 20.minutes,
          end_time:   now,
        }))
      end
    end
  end
end
