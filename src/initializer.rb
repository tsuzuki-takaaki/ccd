require "open3"

MYSQL_HOST = '127.0.0.1'
MYSQL_DATABASE = 'ccd'
MYSQL_USER = 'ccd'
MYSQL_PASSWORD = 'password'
MYSQL_SCHEMA_FILE_PATH = File.expand_path("../../sql/schema.sql", __FILE__)

def init_database
  out, status = Open3.capture2("mysql -u#{MYSQL_USER} -p#{MYSQL_PASSWORD} -h#{MYSQL_HOST} #{MYSQL_DATABASE} < #{MYSQL_SCHEMA_FILE_PATH}")
  unless status.success?
    return "Failed to initialize"
  end
end
init_database
