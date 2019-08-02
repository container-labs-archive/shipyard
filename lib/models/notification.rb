# generate these or switch languages

module Shipyard
  class Notification
    def initialize
      @type = 'slack'
    end

    def to_json
      {
        type: @type
      }
    end
  end
end
