require 'rails/railtie'
require 'active_support'

class Nodo::Railtie < Rails::Railtie
  initializer 'nodo' do |app|
    Nodo.env['NODE_ENV'] = Rails.env.to_s
    Nodo.logger = Rails.logger
  end
end
