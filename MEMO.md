# User.createの返り値のインスタンスがidを持っている理由

結論: Adapter(ex. `ActiveRecord::ConnectionAdapters::Mysql2Adapter`)がwrapしている、DBclient(ex. `mysql2`)が最終INSERT時のidを保持するようになっていて、それを参照している

## コードリーディング

- `create`
  - これの戻り値のobjectにidが入る過程を見る必要がある
  - `build`メソッド時点では、idが入っていないため`save`メソッドを見にいく

```ruby
app(dev)> show_source User.create

From: /usr/local/bundle/gems/activerecord-7.2.0/lib/active_record/persistence.rb:33

      def create(attributes = nil, &block)
        if attributes.is_a?(Array)
          attributes.collect { |attr| create(attr, &block) }
        else
          object = new(attributes, &block)
          object.save
          object
        end
      end
```

- `save`
  - <https://github.com/rails/rails/blob/435a6932c6271ab9cf8a11732fc8cacc2e2cdbc0/activerecord/lib/active_record/persistence.rb#L390C5-L394C8>

```ruby
    def save(**options, &block)
      create_or_update(**options, &block)
    rescue ActiveRecord::RecordInvalid
      false
    end
```

- `create_or_update`
  - <https://github.com/rails/rails/blob/435a6932c6271ab9cf8a11732fc8cacc2e2cdbc0/activerecord/lib/active_record/persistence.rb#L891C7-L897C1>

```ruby
    def create_or_update(**, &block)
      _raise_readonly_record_error if readonly?
      return false if destroyed?
      result = new_record? ? _create_record(&block) : _update_record(&block)
      result != false
    end
```

idが割り振られるタイミングはnew_recordのはずなので、`_create_record`を見に行く

- `_create_record`
  - `User._returning_columns_for_insert(User.connection)` => `=> ["id"]`
  - `_write_attribute`で、idに`returning_values`を設定している
    - -> `_insert_record`の戻り値がidの値になる
  - <https://github.com/rails/rails/blob/435a6932c6271ab9cf8a11732fc8cacc2e2cdbc0/activerecord/lib/active_record/persistence.rb#L920C7-L943C10>

```ruby
    # Creates a record with values matching those of the instance attributes
    # and returns its id.
    def _create_record(attribute_names = self.attribute_names)
      attribute_names = attributes_for_create(attribute_names)

      self.class.with_connection do |connection|
        returning_columns = self.class._returning_columns_for_insert(connection)

        returning_values = self.class._insert_record(
          connection,
          attributes_with_values(attribute_names),
          returning_columns
        )

        returning_columns.zip(returning_values).each do |column, value|
          _write_attribute(column, value) if !_read_attribute(column)
        end if returning_values
      end

      @new_record = false
      @previously_new_record = true

      yield(self) if block_given?

      id
    end
```

- `_insert_record`
  - 今回の場合は、`primary_key`を`id`と想定していいので、以下の変数`primary_key`にはidが入り、`primary_key_value`はnilの状態
  - `prefetch_primary_key?`
    - <https://github.com/rails/rails/blob/435a6932c6271ab9cf8a11732fc8cacc2e2cdbc0/activerecord/lib/active_record/model_schema.rb#L404C7-L408C10>
    - こいつはwrapperメソッドで、`ActiveRecord::ConnectionAdapters::Mysql2Adapter#prefetch_primary_key?`をcallする
    - `User.connection.prefetch_primary_key?`はfalseになりそう(ここはもう少し追いたい)
    - なので、この条件分岐には入らない
  - で、`connection.insert`に到達(その前の処理は割愛)
    - `ActiveRecord::ConnectionAdapters::Mysql2Adapter#insert`

```ruby
      def _insert_record(connection, values, returning) # :nodoc:
        primary_key = self.primary_key
        primary_key_value = nil

        if prefetch_primary_key? && primary_key
          values[primary_key] ||= begin
            primary_key_value = next_sequence_value
            _default_attributes[primary_key].with_cast_value(primary_key_value)
          end
        end

        im = Arel::InsertManager.new(arel_table)

        with_connection do |c|
          if values.empty?
            im.insert(connection.empty_insert_statement_value(primary_key))
          else
            im.insert(values.transform_keys { |name| arel_table[name] })
          end

          connection.insert(
            im, "#{self} Create", primary_key || false, primary_key_value,
            returning: returning
          )
        end
      end
```

- `ActiveRecord::ConnectionAdapters::Mysql2Adapter#insert`
  - <https://github.com/rails/rails/blob/435a6932c6271ab9cf8a11732fc8cacc2e2cdbc0/activerecord/lib/active_record/connection_adapters/abstract/database_statements.rb#L195C7-L202C10>
  - **この時点でも`id_value`はnilであるため、最終的に`last_inserted_id(value)`が答え**
- `ActiveRecord::ConnectionAdapters::Mysql2Adapter#last_inserted_id`
  - <https://github.com/rails/rails/blob/435a6932c6271ab9cf8a11732fc8cacc2e2cdbc0/activerecord/lib/active_record/connection_adapters/mysql2/database_statements.rb#L23C11-L29C14>
  - インスタンス変数`@raw_connection`は、`ActiveRecord::ConnectionAdapters::Mysql2Adapter`のconnect時に代入される`Mysql2::Client`のインスタンス
    - <https://github.com/rails/rails/blob/435a6932c6271ab9cf8a11732fc8cacc2e2cdbc0/activerecord/lib/active_record/connection_adapters/mysql2_adapter.rb#L137C9-L141C12>
    - <https://github.com/rails/rails/blob/435a6932c6271ab9cf8a11732fc8cacc2e2cdbc0/activerecord/lib/active_record/connection_adapters/mysql2_adapter.rb#L24C9-L37C12>

```ruby
def last_inserted_id(result)
  if supports_insert_returning?
    super
  else
    @raw_connection&.last_id
  end
end
```

(※ postgresqlを使った場合は、INSERT処理の後にSELECTが走っていそう: <https://github.com/rails/rails/blob/87bee3640b2a135a360c9af13f0e610bef8df131/activerecord/lib/active_record/connection_adapters/postgresql/database_statements.rb#L203C11-L206C14>)

## mysql2

- ActiveRecordを使わずに、ピュアなmysql2を使った場合
  - <https://github.com/tsuzuki-takaaki/ccd/blob/main/src/main.rb>
- INSERT statementを実行しても戻り値はない
  - が、**cilentは最後に実行したINSERTのidを保持するようになっている**ため、clientで参照することができる
  - mysql2に`last_id`が入ったPR
    - <https://github.com/brianmario/mysql2/commit/e20df5c140b84d9f91f23d7219033e3a537945a3>
    - mysql2で生成したclientでは`last_id`で参照できるが、Cのレベルの`mysql_insert_id`にbindされている
    - <https://dev.mysql.com/doc/c-api/8.0/en/mysql-insert-id.html>

```ruby
require 'mysql2'

MYSQL_HOST = ENV['MYSQL_HOST']
MYSQL_DATABASE = ENV['MYSQL_DATABASE']
MYSQL_USER = ENV['MYSQL_USER']
MYSQL_PASSWORD = ENV['MYSQL_PASSWORD']

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

puts "result: #{result}"
puts "last_insert_id: #{mysql_client.last_id}"
```

```c
/* call-seq:
 *    client.last_id
 *
 * Returns the value generated for an AUTO_INCREMENT column by the previous INSERT or UPDATE
 * statement.
 */
static VALUE rb_mysql_client_last_id(VALUE self) {
  GET_CLIENT(self);
  REQUIRE_CONNECTED(wrapper);
  return ULL2NUM(mysql_insert_id(wrapper->client));
}
```

```sql
SELECT LAST_INSERT_ID();
```
