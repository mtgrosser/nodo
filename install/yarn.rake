namespace :yarn do
  desc 'Clear installed yarn packages'
  task :clear do
    modules_root = Rails.root.join('vendor', 'node_modules')
    modules_root.rmtree if modules_root.exist?
  end
  
  desc 'Install all JavaScript dependencies as specified via Yarn'
  task :install do
    # Install only production deps when for not usual envs.
    valid_node_envs = %w[test development production]
    node_env = ENV.fetch("NODE_ENV") do
      valid_node_envs.include?(Rails.env) ? Rails.env : "production"
    end

    yarn_flags = '--cwd vendor --no-progress --non-interactive --frozen-lockfile'

    Dir.chdir(Rails.root) do
      sh({ "NODE_ENV" => node_env }, "yarn install #{yarn_flags}")
    end
  end
end
