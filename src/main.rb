require 'mysql2'

MYSQL_HOST = '127.0.0.1'
MYSQL_DATABASE = 'ccd'
MYSQL_USER = 'ccd'
MYSQL_PASSWORD = 'password'
MYSQL_SCHEMA_FILE_PATH = File.expand_path("../../sql/schema.sql", __FILE__)

mysql_client = Mysql2::Client.new(
  host: MYSQL_HOST,
  database: MYSQL_DATABASE,
  username: MYSQL_USER,
  password: MYSQL_PASSWORD
)

def build_user_insert_statement(name:, email:)
  "INSERT INTO `user` (`name`, `email`) VALUES ('#{name}', '#{email}');"
end

result = mysql_client.query(build_user_insert_statement(name: 'hoge', email: 'fuga'))

puts "result: #{result}" # This will return nothing
puts "last_insert_id: #{mysql_client.last_id}"
