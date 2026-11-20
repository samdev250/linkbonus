// ISO 3166-1 country and territory codes grouped into familiar regions.
// Names come from browser locale data and flags use Unicode regional indicators.
export const countryRegions: Record<string, string[]> = {
  'East Africa': 'BI KM DJ ER ET KE MG MW MU MZ RE RW SC SO SS SD TZ UG YT'.split(' '),
  'West Africa': 'BJ BF CV CI GM GH GN GW LR ML MR NE NG SN SL TG'.split(' '),
  'Central Africa': 'AO CM CF TD CG CD GQ GA ST'.split(' '),
  'North Africa': 'DZ EG LY MA TN EH'.split(' '),
  'Southern Africa': 'BW LS NA ZA SZ ZM ZW'.split(' '),
  'Northern Europe': 'AX DK EE FO FI GG IS IE IM JE LV LT NO SJ SE GB'.split(' '),
  'Western Europe': 'AT BE FR DE LI LU MC NL CH'.split(' '),
  'Southern Europe': 'AL AD BA HR GI GR IT MT ME MK PT SM RS SI ES VA'.split(' '),
  'Eastern Europe': 'BY BG CZ HU MD PL RO RU SK UA'.split(' '),
  'Central Asia': 'KZ KG TJ TM UZ'.split(' '),
  'East Asia': 'CN HK JP MO MN KP KR TW'.split(' '),
  'Southeast Asia': 'BN KH ID LA MY MM PH SG TH TL VN'.split(' '),
  'South Asia': 'AF BD BT IN MV NP PK LK'.split(' '),
  'West Asia': 'AM AZ BH CY GE IR IQ IL JO KW LB OM PS QA SA SY TR AE YE'.split(' '),
  'North America': 'BM CA GL PM US'.split(' '),
  'Central America': 'BZ CR SV GT HN MX NI PA'.split(' '),
  Caribbean: 'AI AG AW BS BB BQ VG KY CU CW DM DO GD GP HT JM MQ MS PR BL KN LC MF VC SX TT TC VI'.split(' '),
  'South America': 'AR BO BR CL CO EC FK GF GY PY PE SR UY VE'.split(' '),
  'Australia & New Zealand': 'AU NZ'.split(' '),
  'Pacific Islands': 'AS CK FJ PF GU KI MH FM NR NC NU NF MP PW PG WS SB TK TO TV VU WF'.split(' '),
  'Other territories': 'AQ BV IO CX CC HM UM PN SH GS SS TA'.split(' '),
};

const names = new Intl.DisplayNames(['en'], { type: 'region' });
export const countryName = (code: string) => names.of(code) ?? code;
export const flagEmoji = (code: string) => String.fromCodePoint(...Array.from(code.toUpperCase(), char => 127397 + char.charCodeAt(0)));
