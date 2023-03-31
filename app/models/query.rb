class Query < ApplicationRecord
  belongs_to :message
  has_one :response
end
