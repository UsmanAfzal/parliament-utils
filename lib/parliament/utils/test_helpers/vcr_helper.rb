module Parliament
  module Utils
    module TestHelpers
      module VCRHelper
        begin
          require 'vcr'

          LOADED_VCR = true
        rescue LoadError
          puts 'VCR Helper could not find VCR. This may be expected in production environments.'

          LOADED_VCR = false
        end

        def self.load_rspec_config(config)
          return unless LOADED_VCR

          # URIs that appear frequently
          parliament_uri = 'http://localhost:3030'
          bandiera_uri   = 'http://localhost:5000'
          opensearch_uri = 'https://apidataparliament.azure-api.net/search/description'
          hybrid_bills_uri = 'https://localhost:5050'

          VCR.configure do |config|
            config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
            config.hook_into :webmock
            config.configure_rspec_metadata!

            config.default_cassette_options = {
              # record: :new_episodes
              record: :once
            }

            # Create a simple matcher which will 'filter' any request URIs on the fly
            config.register_request_matcher :filtered_uri do |request_1, request_2|
              parliament_match   = request_1.uri.sub(ENV['PARLIAMENT_BASE_URL'], parliament_uri) == request_2.uri.sub(ENV['PARLIAMENT_BASE_URL'], parliament_uri) if ENV['PARLIAMENT_BASE_URL']
              bandiera_match     = request_1.uri.sub(ENV['BANDIERA_URL'], bandiera_uri) == request_2.uri.sub(ENV['BANDIERA_URL'], bandiera_uri) if ENV['BANDIERA_URL']
              opensearch_match   = request_1.uri.sub(ENV['OPENSEARCH_DESCRIPTION_URL'], opensearch_uri) == request_2.uri.sub(ENV['OPENSEARCH_DESCRIPTION_URL'], opensearch_uri) if ENV['OPENSEARCH_DESCRIPTION_URL']
              hybrid_bills_match = request_1.uri.sub(ENV['HYBRID_BILL_API_BASE_URL'], hybrid_bills_uri) == request_2.uri.sub(ENV['HYBRID_BILL_API_BASE_URL'], hybrid_bills_uri) if ENV['HYBRID_BILL_API_BASE_URL']

              parliament_match || bandiera_match || opensearch_match || hybrid_bills_match
            end

            config.default_cassette_options = { match_requests_on: %i[method filtered_uri] }

            # Dynamically filter our sensitive information
            config.filter_sensitive_data('<AUTH_TOKEN>')   { ENV['PARLIAMENT_AUTH_TOKEN'] }       if ENV['PARLIAMENT_AUTH_TOKEN']
            config.filter_sensitive_data(parliament_uri)   { ENV['PARLIAMENT_BASE_URL'] }         if ENV['PARLIAMENT_BASE_URL']
            config.filter_sensitive_data(bandiera_uri)     { ENV['BANDIERA_URL'] }                if ENV['BANDIERA_URL']
            config.filter_sensitive_data(opensearch_uri)   { ENV['OPENSEARCH_DESCRIPTION_URL'] }  if ENV['OPENSEARCH_DESCRIPTION_URL']
            config.filter_sensitive_data(hybrid_bills_uri) { ENV['HYBRID_BILL_API_BASE_URL'] }    if ENV['HYBRID_BILL_API_BASE_URL']

            # Dynamically filter n-triple data
            config.before_record do |interaction|
              should_ignore = ['_:node', '^^<http://www.w3.org/2001/XMLSchema#date>', '^^<http://www.w3.org/2001/XMLSchema#dateTime>', '^^<http://www.w3.org/2001/XMLSchema#integer>']

              # Check if content type header exists and if it includes application/n-triples
              if interaction.response.headers['Content-Type']&.include?('application/n-triples')
                # Split our data by line
                lines = interaction.response.body.split("\n")

                # How many times have we seen a predicate?
                predicate_occurrances = Hash.new(1)

                # Iterate over each line, decide if we need to filter it.
                lines.each do |line|
                  next if should_ignore.any? { |condition| line.include?(condition) }
                  next unless line.include?('"')

                  # require 'pry'; binding.pry
                  # Split on '> <' to get a Subject and Predicate+Object split
                  subject, predicate_and_object = line.split('> <')

                  # Get the actual object
                  predicate, object = predicate_and_object.split('> "')

                  # Get the last part of a predicate URI
                  predicate_type = predicate.split('/').last

                  # Get the number of times we've seen this predicate
                  occurrance = predicate_occurrances[predicate_type]
                  predicate_occurrances[predicate_type] = predicate_occurrances[predicate_type] + 1

                  # Try and build a new object value based on the predicate
                  new_object = "#{predicate_type} - #{occurrance}\""

                  # Replace the object value
                  index = object.index('"')

                  object[0..index] = new_object if index

                  new_line = "#{subject}> <#{predicate}> \"#{object}"
                  config.filter_sensitive_data(new_line) { line }
                end
              end
            end
          end

          config
        end
      end
    end
  end
end
