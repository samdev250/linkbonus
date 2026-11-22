import {BadgeCheck, Gift, Mail, Sparkles} from 'lucide-react';
import './direct-bonus.css';

const format = (value: number) => new Intl.NumberFormat('en-US').format(value);

const tiers = [
  { capital: 100000, bonus: 450000 },
  { capital: 200000, bonus: 900000 },
  { capital: 300000, bonus: 1350000 },
  { capital: 400000, bonus: 1800000 },
  { capital: 500000, bonus: 2250000 },
  { capital: 600000, bonus: 2700000 },
  { capital: 700000, bonus: 3150000 },
  { capital: 800000, bonus: 3600000 },
  { capital: 900000, bonus: 4050000 },
];

export const SUPPORT_EMAIL = 'infolinkbonusinvest@gmail.com';

export const isBurundi = (country?: string, currency?: string) =>
  /^(BI|BURUNDI)$/i.test(String(country ?? '').trim()) || String(currency ?? '').toUpperCase() === 'BIF';

export function DirectBonusPanel({compact = false}: {compact?: boolean}) {
  return <section className={`direct-bonus ${compact ? 'compact' : ''}`}>
    <div className="direct-bonus-head">
      <span className="direct-bonus-chip"><Gift size={14}/> DIRECT BONUS · BURUNDI</span>
      <h2>LINK BONUS <span className="direct-bonus-flags" aria-label="Burundi">🇧🇮🇧🇮🇧🇮🇧🇮🇧🇮🇧🇮🇧🇮🇧🇮</span></h2>
      <p>Uko uronka bonus bijyanye n'ingano y'umutahe watanguje.</p>
    </div>

    <div className="direct-bonus-rules">
      <article><span>01</span><div><b>Ibihugu byemerewe</b><p>Kwinjira muri Link Bonus kubantu bari Burundi, usabwa umutahe guhera kuri <strong>100.000 BIF</strong> kuzamura kugeza kuri <strong>10.000.000 BIF</strong>.</p></div></article>
      <article><span>02</span><div><b>Welcome bonus</b><p>Uhabwa bonus ubwo nyine uhejeje gushyiramo umutahe: <strong>5% kumunsi</strong>, kandi uhabwa inyungu y'<strong>iminsi 90</strong> nka welcome bonus.</p></div></article>
      <article><span>03</span><div><b>Uko uhitamo</b><p>Raba lisiti y'imitahe n'ibonus, hanyuma uhitemo ayo watanguza.</p></div></article>
    </div>

    <div className="direct-bonus-list">
      <div className="direct-bonus-list-head"><div><span className="eyebrow">IMITAHE N'IBONUS</span><h3>Raba lisiti y'imitahe n'ibonus</h3></div><span className="direct-bonus-cheer" aria-hidden="true">🦸🏾‍♀️🦸🏾‍♀️🦸🏾‍♀️</span></div>
      <div className="direct-bonus-table-wrap"><table className="direct-bonus-table"><thead><tr><th>Umutahe watanguje</th><th>Bonus uhabwa</th></tr></thead><tbody>{tiers.map(({capital, bonus}) => <tr key={capital}><td><span className="bonus-dot"/>{format(capital)} BIF</td><td><strong>{format(bonus)} BIF</strong></td></tr>)}</tbody></table></div>
    </div>

    <div className="direct-bonus-premium">
      <div className="direct-bonus-premium-head"><Sparkles size={18}/><div><span className="eyebrow">UMUTAHE WA 1.000.000 BIF KUZAMURA</span><h3>Bonus zose nta kimwe gikuwemo</h3></div></div>
      <p>Kubantu batanguza umutahe guhera kuri <strong>1.000.000 BIF</strong> kuzamura, bahabwa bonus zabo zose nta kimwe gikuwemo. Ahabwa inyungu y'amezi 3 (iminsi 90) ya <strong>10% kumunsi</strong>, bitandukanye n'abandi bahabwa 5% ukubye iminsi. Kuri 1 Million uronka inyungu ya <strong>9.000.000 FBu</strong> ingana n'amezi 3. Nta kindi kintu usabwa: direct akimara kwinjira.</p>
      <div className="direct-bonus-stats"><div><b>10%</b><small>kumunsi</small></div><div><b>Iminsi 90</b><small>amezi 3</small></div><div><b>9.000.000</b><small>FBu kuri 1M</small></div></div>
      <p className="direct-bonus-agent"><BadgeCheck size={16}/> Umuntu utanguza umutahe guhera kuri 1.000.000 BIF aba yemerewe gusaba kuba umu-agent wa Company mu gihe abishoboye. Murakoze, ni karibu.</p>
    </div>

    <footer className="direct-bonus-footer"><Mail size={15}/><span>Twandikire kubundi busobanuro</span><a href={`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent('LINK BONUS Direct Bonus')}`}>{SUPPORT_EMAIL}</a></footer>
  </section>;
}
