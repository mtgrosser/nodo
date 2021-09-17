require 'rails/railtie'
require 'active_support'

class Jass::Core::Railtie < Rails::Railtie
  config.jass = ActiveSupport::OrderedOptions.new

  initializer 'jass' do |app|
    Jass.modules_root = Rails.root.join('vendor', 'node_modules')
  end
end
