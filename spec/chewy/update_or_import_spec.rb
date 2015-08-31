require 'spec_helper'

describe Chewy::Type::UpdateOrImport do
  before { Chewy.massacre }

  before do
    stub_class(:city, Struct.new(:id, :name, :population))
    stub_class(:country, Struct.new(:id, :name, :cities, :capital))
  end

  before do
    stub_index(:countries) do
      define_type Country do
        field :name
        field :cities do
          field :id
          field :name
          field :population, type: 'integer'
        end
        field :capital do
          field :id
          field :name
          field :population, type: 'integer'
        end
      end
    end
  end

  let(:country) { CountriesIndex::Country }

  let(:moscow) { City.new 1, 'Moscow', 12_000_000 }
  let(:spb) { City.new 2, 'Saint Petersbug', 4_800_000 }
  let(:arkhangelsk) { City.new 3, 'Arkhangelsk', 348_000 }
  let(:washington) { City.new 4, 'Washington', 658_000 }

  let(:russia) { Country.new 1001, 'Russia', [moscow, spb, arkhangelsk], moscow }
  let(:usa) { Country.new 1002, 'United States of America', [washington], washington }

  it 'updates only requested fields' do
    Chewy.logger = Logger.new(STDOUT)
    country.import! russia

    moscow.population += 1
    country.update_or_import russia, only: [:capital]
    found = country.find(1001)
    expect(found.capital['population']).to eq(12_000_001)
    expect(found.cities.first['population']).to eq(12_000_000)

    moscow.population += 1
    moscow.name = 'Moskva'
    country.update_or_import russia, only: [:cities, { capital: [:name] }]
    found = country.find(1001)
    expect(found.capital['name']).to eq('Moskva')
    expect(found.capital['population']).to eq(12_000_001)
    expect(found.cities.first['population']).to eq(12_000_002)
    expect(found.cities.first['name']).to eq('Moskva')
  end
end
