source "https://rubygems.org"

gemspec
gem 'rdf',              git: "git://github.com/ruby-rdf/rdf.git", branch: "develop"
gem 'rdf-spec',         git: "git://github.com/ruby-rdf/rdf-spec.git", branch: "develop"
gem 'jsonlint',         git: "git://github.com/dougbarth/jsonlint.git", platforms: [:rbx, :mri]

group :development do
  gem 'rdf-turtle',     git: "git://github.com/ruby-rdf/rdf-turtle.git", branch: "develop"
  gem 'rdf-trig',       git: "git://github.com/ruby-rdf/rdf-trig.git", branch: "develop"
  gem 'rdf-vocab',      git: "git://github.com/ruby-rdf/rdf-vocab.git", branch: "develop"
  gem 'fasterer'
  gem "wirble"
  gem "linkeddata"
  gem "byebug", platforms: [:mri_20, :mri_21]
end

group :development, :test do
  gem 'simplecov',  require: false, platform: :mri_21 # Travis doesn't understand 22 yet.
  gem 'coveralls',  require: false, platform: :mri_21 # Travis doesn't understand 22 yet.
end

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'rubinius', '~> 2.0'
end
