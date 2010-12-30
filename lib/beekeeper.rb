%w(
	net/http
	json
).each &method(:require)

# The module containing the interface to Beehive.  You are likely to be
# interested in Beekeeper::Client for interactions with Beehive through Ruby.
module Beekeeper
	# The exception class from which all Beekeeper errors originate.
	class Error < ::StandardError; end
	# The client has attempted to access a resource, but is not authenticated.
	class AuthenticationError < Error; end

	# The Client class represents a single client for a Beehive server.  The
	# typical life of a client is like this:
	# 
	# Instantiate a client (see DefaultOpts):
	#	c = Beekeeper::Client.new :save_auth => true
	# Authenticate, using ~/.beehive_auth (because we told it to do that
	# above):
	#	c.authenticate!	# Loads auth data from a file, since we told it to.
	# Create a basic rack application, now that we're authenticated:
	#	c.create_app 'super-app', 'rack', 'git://example.com/git/super-app.git'
	# Ask the server what the app looks like:
	#	p c.apps['super-app']
	class Client
		# The default set of options, which may be passed at initialization
		# time or altered after initialization through Beekeeper::Client#opts .
		DefaultOpts = {
			# Should auth tokens be saved to or read from a file?
			:save_auth => false,
			# The location of the auth file.  The file is JSON-formatted.  It's
			# also cleartext, so use this option (and :save_auth) with care.
			:auth_file => "#{ENV['HOME']}/.beehive_auth",
			# The connection information for the server, as [host, port].
			:server => ['localhost', 4999],
			# Use HTTPS when talking to the server?
			:ssl => false,
		}

		attr_accessor :opts, :auth_token

		# Creates a client, optionally with a list of options, as a hash.
		# Supported options and their defaults are found in
		# Beekeeper::Client::DefaultOpts .
		def initialize opts = {}
			self.opts = DefaultOpts.merge opts
		end

		# Attempts to authenticate a user based on email and password, which
		# may be passed in, or may be loaded from opts[:auth_file] if
		# opts[:save_auth] is true.  If the options are passed in and
		# opts[:save_auth] is true, then they authorization will be saved.
		def authenticate! email = nil, pass = nil
			if email.nil? || pass.nil?
				if opts[:save_auth]
					email, pass = load_auth
				end
			else
				save_auth(email, pass) if opts[:save_auth]
			end

			return nil if(email.nil? || pass.nil?)

			!!grab_token!(email, pass)
		end

		# Creates an application with the specified name and template, and tell
		# the server that it can be found at repo_url (which must be a git
		# repository; if the repository is local, it must be written as a
		# "file://" URL).
		def create_app name, template, repo_url
			data = {
				'name' => name,
				'template' => template,
				'repo_url' => repo_url,

				'token' => auth_token,
			}.to_json

			http { |h|
				JSON.parse(h.post('/apps.json', data).body) rescue nil
			}
		end

		def update_app name, opts = {}
			data = {'token' => auth_token}.merge(opts).to_json
			http { |h|
				JSON.parse(h.put("/apps/#{name}.json", data).body) rescue nil
			}
		end

		# Deletes the named application.
		def delete_app name
			delete("/apps/#{name}.json?token=#{auth_token}")
		end

		# Returns a list of applications deployed to Beehive and information
		# about them.
		def apps
			JSON.parse(http { |h|
				h.get("/apps.json?token=#{auth_token}")
			}.body)['apps'] rescue nil
		end

		# Returns a list of bees and some diagnostics about them.
		def bees
			JSON.parse(http { |h|
				h.get("/bees.json?token=#{auth_token}")
			}.body)['bees'] rescue nil
		end

		private

		# Returns [email, password] or nil.
		def load_auth
			begin
				authdata = JSON.parse(File.read(opts[:auth_file]))
				[authdata['email'], authdata['password']]
			rescue
			end
		end

		def save_auth email, pass
			js = JSON.pretty_unparse({'email' => email, 'password' => pass})

			begin
				File.open(opts[:auth_file], 'w') { |f| f.puts js }
			rescue
				return false
			end

			true
		end

		# Returns an auth token (and sets self.auth_token), or returns nil if
		# the server is involved in or wasn't having any of our shenanigans.
		def grab_token! email, pass
			r = post('/auth.json',
			         {'email' => email, 'password' => pass}.to_json)
			return nil unless r

			begin
				authdata = JSON.parse r.body
				self.auth_token = authdata['token']
			rescue
			end
		end

		def http
			Net::HTTP.new(*opts[:server]).start { |http|
				http.use_ssl = opts[:ssl]
				yield http if block_given?
			}
		end

		def get path
			http { |h| h.get path }
		end

		def delete path
			http { |h| h.delete path }
		end

		def post path, body = nil
			http { |h| h.post path, body }
		end

		def put path, body = nil
			http { |h| h.put path, body }
		end
	end

	class Commands
	end
end
