class MockRedis
  class FutureNotReady < RuntimeError; end

  class Future
    attr_reader :command

    def initialize(command)
      @command = command
      @result_set = false
    end

    def value
      raise FutureNotReady unless @result_set
      @result
    end

    def set_result(result)
      @result_set = true
      @result = result
    end
  end

  class PipelinedWrapper
    include UndefRedisMethods

    def respond_to?(method, include_private=false)
      super || @db.respond_to?(method)
    end

    def initialize(db)
      @db = db
      @pipelined_futures = []
      @in_pipeline = false
    end

    def initialize_copy(source)
      super
      @db = @db.clone
      @pipelined_futures = @pipelined_futures.clone
    end

    def method_missing(method, *args, &block)
      if @in_pipeline
        future = MockRedis::Future.new([method, *args])
        @pipelined_futures << future
        future
      else
        @db.send(method, *args, &block)
      end
    end

    def pipelined(options = {})
      @in_pipeline = true
      yield self
      @in_pipeline = false
      responses = @pipelined_futures.map do |future|
        begin
          result = send(*future.command)
          future.set_result(result)
          result
        rescue => e
          e
        end
      end
      @pipelined_futures = []
      responses
    end
  end
end
