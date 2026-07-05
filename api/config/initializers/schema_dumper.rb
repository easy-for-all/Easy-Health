# knowledge_chunks has a pgvector "vector" column that ActiveRecord's schema
# dumper cannot represent in Ruby (no `neighbor`/pgvector type registered),
# and no migration for this table exists in this repo (it predates this
# initializer). Left untouched in the database; only excluded from schema.rb
# so dumps stay loadable (a dangling add_foreign_key to a table with no
# create_table otherwise breaks db:schema:load / db:test:prepare).
ActiveRecord::SchemaDumper.ignore_tables = ["knowledge_chunks"]
