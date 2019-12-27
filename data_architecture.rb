# frozen_string_literal: true

begin
  require "bundler/inline"
rescue LoadError => e
  $stderr.puts "Bundler version 1.10 or later is required. Please update your Bundler"
  raise e
end

gemfile(true) do
  source "https://rubygems.org"

  gem "activerecord"
  gem "pg"
end

require "active_record"

db_name = ENV.fetch("DB_NAME", "carbon_challenge")
db_user = ENV.fetch("DB_USER", "postgres")
db_config = {
  "host" => :localhost, "adapter" => :postgresql, "database" => db_name, "username" => db_user
}
ActiveRecord::Base.establish_connection(db_config)
begin
  ActiveRecord::Base.connection
rescue ActiveRecord::NoDatabaseError
  ActiveRecord::Tasks::DatabaseTasks.create(db_config)
  ActiveRecord::Base.establish_connection(db_config)
end

ActiveRecord::Schema.define do
  execute <<~ENUMS
    DROP TYPE IF EXISTS asset_class, instrument_type CASCADE;

    CREATE TYPE asset_class AS ENUM (
      'equity', 'fixed_income', 'cash_equivalent', 'commodity', 'real_estate'
    );

    CREATE TYPE instrument_type AS ENUM (
      'cash', 'certificate_of_deposit', 'etf', 'futures_contract', 'loan',
      'mortgage', 'muni_bond', 'mutual_fund', 'reits', 'stock', 'treasuries'
    );
  ENUMS

  enable_extension "pgcrypto"

  create_table :esg_scores, force: :cascade do |t|
    t.belongs_to :holder, null: false, polymorphic: true, type: :uuid
    t.decimal :environmental, scale: 6, precision: 7, null: false
    t.decimal :social, scale: 6, precision: 7, null: false
    t.decimal :governance, scale: 6, precision: 7, null: false
    t.timestamps
  end

  create_table :instruments, force: :cascade, id: :uuid do |t|
    t.string :isin, null: false
    t.string :name, null: false
    t.column :instrument_type, :instrument_type, null: false
    t.column :asset_class, :asset_class, null: false
    t.timestamps
  end

  add_index :instruments, :isin, unique: true

  create_table :holdings, force: :cascade do |t|
    t.belongs_to :holder, type: :uuid, polymorphic: true
    t.belongs_to :instrument, type: :uuid, foreign_key: true
    t.decimal :weight, scale: 10, precision: 11
    t.timestamps
  end

  create_table :companies, force: :cascade, id: :uuid do |t|
    t.text :name, null: false
    t.text :description
    t.timestamps
  end

  create_table :clients, force: :cascade, id: :uuid do |t|
    t.string :name, null: false
    t.timestamps
  end

  create_table :portfolios, force: :cascade, id: :uuid do |t|
    t.string :name, null: false
    t.text :description
    t.belongs_to :client, null: false, foreign_key: true, type: :uuid
    t.timestamps
  end
end

class EsgScore < ActiveRecord::Base
  belongs_to :holder, polymorphic: true

  validates :social, presence: true, numericality: {
    greater_than_or_equal_to: 0, less_than_or_equal_to: 1
  }
  validates :environmental, presence: true, numericality: {
    greater_than_or_equal_to: 0, less_than_or_equal_to: 1
  }
  validates :governance, presence: true, numericality: {
    greater_than_or_equal_to: 0, less_than_or_equal_to: 1
  }

  scope :latest, -> { order(created_at: :desc) }

  def score(round: 8)
    ((social + environmental + governance) / 3.to_d).round(round)
  end
end

class Holding < ActiveRecord::Base
  belongs_to :instrument
  belongs_to :holder, polymorphic: true

  validates :weight, presence: true, numericality: {
    greater_than_or_equal_to: 0, less_than_or_equal_to: 1
  }
end

class Instrument < ActiveRecord::Base
  has_many :holdings, as: :holder
  has_many :instruments, through: :holdings
  has_many :esg_scores, as: :holder
  has_one :latest_esg_score, -> { latest }, as: :holder, class_name: 'EsgScore'

  enum instrument_type: {
    cash: :cash,
    certificate_of_deposit: :certificate_of_deposit,
    etf: :etf,
    futures_contract: :futures_contract,
    loan: :loan,
    mortgage: :mortgage,
    muni_bond: :muni_bond,
    mutual_fund: :mutual_fund,
    reits: :reits,
    stock: :stock,
    treasuries: :treasuries
  }
  enum asset_class: {
    equity: :equity,
    fixed_income: :fixed_income,
    cash_equivalent: :cash_equivalent,
    commodity: :commodity,
    real_estate: :real_estate
  }

  validates :name, presence: true
  validates :instrument_type, presence: true
  validates :asset_class, presence: true
end

class Company < ActiveRecord::Base
  has_many :holdings, as: :holder
  has_many :esg_scores, as: :holder
  has_one :latest_esg_score, -> { latest }, as: :holder, class_name: 'EsgScore'

  validates :name, presence: true
end

class Portfolio < ActiveRecord::Base
  belongs_to :client
  has_many :holdings, as: :holder
  has_many :esg_scores, as: :holder
  has_one :latest_esg_score, -> { latest }, as: :holder, class_name: 'EsgScore'

  validates :name, presence: true
end

class Client < ActiveRecord::Base
  has_many :portfolios

  validates :name, presence: true
end

client = Client.create!(name: "Trevor")
portfolio = client.portfolios \
  .create!(name: "Trevors Portfolio", description: "all cash")
apple = Company.create!(name: "Apple", description: "Think Different")
google = Company.create!(name: "Google", description: "Don't be evil")
apple_hq = Instrument.create!(
  isin: "applehq1", name: "Apple Headquarters",
  instrument_type: :mortgage, asset_class: :real_estate
)
google_hq = Instrument.create!(
  isin: "googlehq1", name: "Google Headquarters",
  instrument_type: :mortgage, asset_class: :real_estate
)
etf = Instrument.create!(
  isin: "ETF", name: "My ETF", instrument_type: :etf, asset_class: :real_estate
)
Holding.create!(holder: etf, instrument: apple_hq, weight: 0.2)
Holding.create!(holder: etf, instrument: google_hq, weight: 0.2)
Holding.create!(holder: apple, instrument: apple_hq, weight: 0.8)
Holding.create!(holder: google, instrument: google_hq, weight: 0.7)
Holding.create!(holder: portfolio, instrument: google_hq, weight: 0.1)
Holding.create!(holder: portfolio, instrument: etf, weight: 0.1)
EsgScore.create!(
  holder: apple, environmental: 0.002, social: 0.4, governance: 0.8
)
EsgScore.create!(
  holder: google, environmental: 0.008, social: 0.002, governance: 1
)
EsgScore.create!(
  holder: portfolio, environmental: 0.8, social: 0.3, governance: 0.6
)

def display(company)
  holdings = company.holdings.joins(:instrument) \
    .pluck("instruments.name, holdings.weight") \
    .flat_map{ |x| x.join(' - ') }
  <<~DISPLAY
    #{company.name}:
      ESG Score: #{company.latest_esg_score&.score || "NA"}
      Holdings: #{holdings}"
  DISPLAY
end

puts display(apple)
puts display(google)
puts display(portfolio)

