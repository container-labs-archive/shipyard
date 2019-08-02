# generate these or switch languages

module Shipyard
  class Trigger
    def initialize
      @type = 'pipeline'
    end

    def to_json
      {
        type: @type
      }
    end
  end
end
