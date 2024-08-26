require 'nokogiri'
require 'httparty'
require 'watir'

TEAM_URLS = {
  'aek': 'https://footystats.org/clubs/aek-athens-fc-1101',
  'antwerp': 'https://footystats.org/clubs/royal-antwerp-fc-1048',
  'aris': 'https://footystats.org/clubs/aris-thessaloniki-fc-5131',
  'arsenal': 'https://footystats.org/clubs/arsenal-fc-59',
  'asteras_tripolis': 'https://footystats.org/clubs/asteras-tripolis-fc-1107',
  'atalanta': 'https://footystats.org/clubs/atalanta-bergamasca-calcio-464',
  'atromitos': 'https://footystats.org/clubs/pae-aps-atromitos-athens-1109',
  'barnsley': 'https://footystats.org/clubs/barnsley-fc-215',
  'benfica': 'https://footystats.org/clubs/sl-benfica-78',
  'bolton': 'https://footystats.org/clubs/bolton-wanderers-fc-226',
  'bournemouth': 'https://footystats.org/clubs/afc-bournemouth-148',
  'braga': 'https://footystats.org/clubs/sporting-braga-172',
  'bristol_rovers': 'https://footystats.org/clubs/bristol-rovers-fc-244',
  'cameroon': 'https://footystats.org/clubs/cameroon-national-team-8634',
  'celta': 'https://footystats.org/clubs/real-club-celta-de-vigo-281',
  'charlton': 'https://footystats.org/clubs/charlton-athletic-fc-225',
  'chelsea': 'https://footystats.org/clubs/chelsea-fc-152',
  'cheltenham': 'https://footystats.org/clubs/cheltenham-town-fc-260',
  'derby': 'https://footystats.org/clubs/derby-county-fc-213',
  'dinamo_zagreb': 'https://footystats.org/clubs/gnk-dinamo-zagreb-122',
  'dortmund': 'https://footystats.org/clubs/bvb-09-borussia-dortmund-33',
  'exeter': 'https://footystats.org/clubs/exeter-city-fc-268',
  'fortuna_sittard': 'https://footystats.org/clubs/fortuna-sittard-387',
  'gambia': 'https://footystats.org/clubs/gambia-national-team-8703',
  'giannina': 'https://footystats.org/clubs/pas-giannina-fc-1098',
  'gil_vicente': 'https://footystats.org/clubs/gil-vicente-fc-183',
  'groningen': 'https://footystats.org/clubs/fc-groningen-372',
  'guimaraes': 'https://footystats.org/clubs/vitoria-guimaraes-sc-175',
  'kallithea': 'https://footystats.org/clubs/gs-kallithea-fc-5132',
  'kifisia': 'https://footystats.org/clubs/kifisias-fc-5168',
  'lamia': 'https://footystats.org/clubs/pas-lamia-1964-1104',
  'levadeiakos': 'https://footystats.org/clubs/levadiakos-fc-1108',
  'liverpool': 'https://footystats.org/clubs/liverpool-fc-151',
  'lokomotiva_zagreb': 'https://footystats.org/clubs/nk-lokomotiva-zagreb-1859',
  'luzern': 'https://footystats.org/clubs/fc-luzern-890',
  'maccabi_tel_aviv': 'https://footystats.org/clubs/maccabi-tel-aviv-fc-956',
  'manchester_city': 'https://footystats.org/clubs/manchester-city-fc-93',
  'manchester_united': 'https://footystats.org/clubs/manchester-united-fc-149',
  'monaco': 'https://footystats.org/clubs/as-monaco-fc-56',
  'northampton': 'https://footystats.org/clubs/northampton-town-fc-242',
  'ofi': 'https://footystats.org/clubs/ofi-fc-5130',
  'olympiakos': 'https://footystats.org/clubs/olympiakos-cfp-116',
  'oostende': 'https://footystats.org/clubs/kv-oostende-531',
  'oxford': 'https://footystats.org/clubs/oxford-united-fc-243',
  'panaitolikos': 'https://footystats.org/clubs/panaitolikos-gfs-agrinio-1103',
  'panathinaikos': 'https://footystats.org/clubs/panathinaikos-fc-960',
  'panserraikos': 'https://footystats.org/clubs/panserraikos-fc-5138',
  'paok': 'https://footystats.org/clubs/paok-thessaloniki-fc-106',
  'porto': 'https://footystats.org/clubs/fc-porto-82',
  'psv': 'https://footystats.org/clubs/psv-eindhoven-121',
  'reading': 'https://footystats.org/clubs/reading-fc-219',
  'real_sociedad': 'https://footystats.org/clubs/real-sociedad-de-futbol-290',
  'rouen': 'https://footystats.org/clubs/fc-de-rouen-1899-7114',
  'servette': 'https://footystats.org/clubs/servette-fc-898',
  'sporting': 'https://footystats.org/clubs/sporting-clube-de-portugal-114',
  'vizela': 'https://footystats.org/clubs/fc-vizela-4841',
  'volos': 'https://footystats.org/clubs/volos-new-football-club-5199',
  'wigan': 'https://footystats.org/clubs/wigan-athletic-fc-221',
  'winthertur': 'https://footystats.org/clubs/fc-winterthur-903',
  'wycombe': 'https://footystats.org/clubs/wycombe-wanderers-fc-266',
  'yverdon': 'https://footystats.org/clubs/yverdon-sport-fc-1074'
}.with_indifferent_access

unless (TEAM_URLS[ARGV[0]] && TEAM_URLS[ARGV[1]])
  puts "Team url(s) not found!"

  return
end

br = Watir::Browser.new
br.goto(TEAM_URLS[ARGV[0]])
br.elements(class: 'mt1e comparison-table-table w100').wait_until(&:present?)
js_doc = br.element(class: 'mt1e comparison-table-table w100')
hsh = Nokogiri::HTML(js_doc.inner_html){ |conf| conf.noblanks };0
xg_home_for = hsh.children.last.children.last.children.last.children[3].children[2].text.to_f
xg_home_against = hsh.children.last.children.last.children.last.children[3].children[1].text.to_f

br = Watir::Browser.new
br.goto(TEAM_URLS[ARGV[1]])
br.elements(class: 'mt1e comparison-table-table w100').wait_until(&:present?)
js_doc = br.element(class: 'mt1e comparison-table-table w100')
hsh = Nokogiri::HTML(js_doc.inner_html){ |conf| conf.noblanks };0
xg_away_for = hsh.children.last.children.last.children.last.children[3].children[3].text.to_f
xg_away_against = hsh.children.last.children.last.children.last.children[3].children[1].text.to_f

scores = []

# cards
# shots
# penalties

res = {
  home: 0,
  draw: 0,
  away: 0,
  under15: 0,
  over15: 0,
  under25: 0,
  over25: 0,
  under35: 0,
  over35: 0,
  gg: 0,
  two_three: 0
}

puts "Simulating games..."

100000.times do
  home = Distribution::Poisson.rng((xg_home_for))
  away = Distribution::Poisson.rng((xg_away_for))
  home_ag = Distribution::Poisson.rng((xg_home_against))
  away_ag = Distribution::Poisson.rng((xg_away_against))

  scores << "#{[home, away_ag].max}-#{[away, home_ag].max}"

  if home == away
    res[:draw] += 1
  elsif home > away
    res[:home] += 1
  else
    res[:away] += 1
  end

  if home + away > 1.5
    res[:over15] += 1
  else
    res[:under15] += 1
  end

  if home + away > 2.5
    res[:over25] += 1
  else
    res[:under25] += 1
  end

  if home + away > 3.5
    res[:over35] += 1
  else
    res[:under35] += 1
  end

  if home.positive? && away.positive?
    res[:gg] += 1
  end

  if [2, 3].include?(home + away)
    res[:two_three] += 1
  end
end

res.transform_values!{ |v| v / 1000.0 }
pp res
pp (scores.tally.transform_values{|x| x/1000.0}.sort_by{|_,v| v}.reverse.take(8))
