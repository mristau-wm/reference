######### Constants and helper methods
END_DATE = Time.current.beginning_of_day - 1.day
FLIGHTS = Advertising::Flight.all

def campaign_revenue_report
  adzerk_campaigns = {}
  revenue_report[:Result][:Records].first[:Details].each do |detail|
    adzerk_campaigns[detail[:Grouping][:CampaignId]] = (detail[:TrueRevenue] * 100).to_i
  end
  return adzerk_campaigns
end

def expected_kevel_lifetime_cap(flight)
  budget_increases(flight) - budget_decreases(flight)
end

def revenue_report
  begin
    receipt = api.create_report(
      group_by: %w[campaignid],
      start_date: Advertising::Flight.order(:created_at).first.created_at,
      end_date: END_DATE
    )
    api.poll_report(report_id: receipt[:Id])
  end
end

def kevel_remaining_budget(flight)
  flight.lifetime_cap - campaign_revenue_report[flight.campaign.id]
end

def available_balance(flight)
  expected_kevel_lifetime_cap(flight) - flight_settled_revenue(flight)
end

def flight_settled_revenue(flight)
  flight.advertising_account.entries.select \
    { |entry| Advertising::Utility.settlement_entry?(entry) }.map \
    { |entry| entry.debit_amounts.first.amount.to_i }.sum
end

def api
  @api ||= Adzerk::Api.new(cache_requests: true)
end

def budget_increases(flight)
  entry_match = /(Transferred from Organization|pretransfer\.cash_overage|whole_dollar_correction)/
  budget_increases = flight.cash_account.credit_entries.where('date <= ?', END_DATE).select \
    { |e| e.description.match(entry_match) }.map \
    { |e| e.credit_amounts.pluck(:amount) }.flatten.sum.to_i
end

def budget_decreases(flight)
  entry_match = /(Transferred from Advertising::Flight)/
  flight.cash_account.debit_entries.where('date <= ?', END_DATE).select \
    { |e| e.description.match entry_match }.map \
    { |e| e.debit_amounts.pluck(:amount) }.flatten.sum.to_i
end

######### Main loop
FLIGHTS.each do |flight|
  if available_balance(flight) == kevel_remaining_budget
    puts "Mismatch found on #{flight.advertiser.name}'s flight ##{flight.id}"
    puts "Available Advertising Campaign Balance: #{available_balance(flight)} - Kevel Remaining Budget: #{kevel_remaining_budget(flight)}"
end
