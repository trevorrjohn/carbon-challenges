# frozen_string_literal: true

require "json"

class CarbonAnalyticCalculator
  def initialize(total_energy_use:, total_co2_equivalents_emissions:,
                 renewable_energy_purchased:, renewable_energy_produced:,
                 carbon_credit_value:)
    @total_energy_use = total_energy_use
    @total_co2_equivalents_emissions = total_co2_equivalents_emissions
    @renewable_energy_purchased = renewable_energy_purchased
    @renewable_energy_produced = renewable_energy_produced
    @carbon_credit_value = carbon_credit_value
  end

  DISCOUNT_FACTOR       = 0.5
  MAX_DISCOUNT_FACTOR   = 0.8
  CO2_CONVERSION_FACTOR = 0.5

  def calculate
    (@total_co2_equivalents_emissions - @carbon_credit_value) *
      (1 - discount_factor) -
      (CO2_CONVERSION_FACTOR * @renewable_energy_produced)
  end

  private

  def discount_factor
    [
      MAX_DISCOUNT_FACTOR,
      DISCOUNT_FACTOR * (@renewable_energy_purchased / @total_energy_use)
    ].min
  end
end

calc1 = CarbonAnalyticCalculator.new(
  total_energy_use: 1000,
  total_co2_equivalents_emissions: 25,
  renewable_energy_purchased: 10,
  renewable_energy_produced: 20,
  carbon_credit_value: 50
)
calc2 = CarbonAnalyticCalculator.new(
  total_energy_use: 100,
  total_co2_equivalents_emissions: 10,
  renewable_energy_purchased: 5,
  renewable_energy_produced: 20,
  carbon_credit_value: 50
)
if calc1.calculate != -35
  $stderr.puts "Invalid calculation when over max discount factor " \
    "expected -35, but got #{calc1.calculate}"
  exit 1
elsif calc2.calculate != -50
  $stderr.puts "Invalid calculation when under max discount factor " \
    "expected 50, but got #{calc2.calculate}"
  exit 1
end

filename = ARGV.size == 1 ? ARGV[0] : "./carbon_calculation/data.json"
JSON.parse(File.read(filename)).each do |data|
  calc = CarbonAnalyticCalculator.new(
    total_energy_use: data["Total Energy Use"],
    total_co2_equivalents_emissions: data["Total CO2 Equivalents Emissions"],
    renewable_energy_purchased: data["Renewable Energy Purchased"],
    renewable_energy_produced: data["Renewable Energy Produced"],
    carbon_credit_value: data["Carbon Credit Value"]
  ).calculate
  puts "#{data["ISIN"]}: #{calc}"
end
