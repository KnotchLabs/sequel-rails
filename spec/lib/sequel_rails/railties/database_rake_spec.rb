require 'spec_helper'

describe 'Database rake tasks', :no_transaction => true do
  let(:app) { Combustion::Application }
  let(:app_root) { app.root }
  let(:schema) { "#{app_root}/db/schema.rb" }

  around do |example|
    begin
      FileUtils.rm schema if File.exist? schema
      example.run
    ensure
      FileUtils.rm schema if File.exist? schema
    end
  end

  describe 'db:schema:dump' do
    it "dumps the schema in 'db/schema.rb'" do
      Dir.chdir app_root do
        `rake db:schema:dump`
        expect(File.exist?(schema)).to be true
      end
    end

    it 'append the migration schema information if any' do
      Dir.chdir app_root do
        `rake db:migrate db:schema:dump`
        sql = Sequel::Model.db.from(
          :schema_migrations
        ).insert_sql(:filename => '1273253849_add_twitter_handle_to_users.rb')
        content = if ENV['TEST_ADAPTER'] == 'postgresql'
                    <<-EOS.strip_heredoc
                      Sequel.migration do
                        change do
                          self << "SET search_path TO \\"$user\\", public"
                          self << #{sql.inspect}
                        end
                      end
                    EOS
                  else
                    <<-EOS.strip_heredoc
                      Sequel.migration do
                        change do
                          self << #{sql.inspect}
                        end
                      end
                    EOS
                  end
        expect(File.read(schema)).to include content
      end
    end
  end

  describe 'db:structure:dump', :skip_jdbc do
    let(:schema) { "#{app_root}/db/structure.sql" }

    it "dumps the schema in 'db/structure.sql'" do
      Dir.chdir app_root do
        `rake db:structure:dump`
        expect(File.exist?(schema)).to be true
      end
    end

    it 'append the migration schema information if any' do
      Dir.chdir app_root do
        `rake db:migrate db:structure:dump`

        sql = Sequel::Model.db.from(
          :schema_migrations
        ).insert_sql(:filename => '1273253849_add_twitter_handle_to_users.rb')
        expect(File.read(schema)).to include sql
      end
    end
  end

  describe 'db:rollback' do
    it 'revert latest migration' do
      Dir.chdir app_root do
        begin
          expect do
            `rake db:rollback`
          end.to change { SequelRails::Migrations.current_migration }.from(
            '1273253849_add_twitter_handle_to_users.rb'
          ).to(nil)
        ensure
          SequelRails::Migrations.migrate_up!
        end
      end
    end
  end

  describe 'db:migrate:redo' do
    it 'run down then up of the latest migration' do
      Dir.chdir app_root do
        SequelRails::Migrations.migrate_up!
        expect do
          `rake db:migrate:redo`
        end.not_to change { SequelRails::Migrations.current_migration }
      end
    end
  end

  describe 'db:sessions:clear' do
    let(:sessions) { Sequel::Model.db.from(:sessions) }

    it 'truncates sessions table' do
      sessions.insert session_id: 'foo', data: ''
      sessions.insert session_id: 'bar', data: ''

      expect { `rake db:sessions:clear` }.to change { sessions.count }.by(-2)
    end
  end

  describe 'db:sessions:trim' do
    let(:sessions) { Sequel::Model.db.from(:sessions) }

    it 'delete sessions before cutoff' do
      sessions.insert session_id: 'foo', data: '', update_at: (Date.today - 60).to_time
      sessions.insert session_id: 'bar', data: '', update_at: Date.today.to_time

      expect { `rake db:sessions:trim` }.to change { sessions.count }.by(-1)
    end
  end
end
