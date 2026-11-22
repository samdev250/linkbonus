import './direct-bonus.css';

export const isBurundi = (country?: string, currency?: string) =>
  /^(BI|BURUNDI)$/i.test(String(country ?? '').trim()) || String(currency ?? '').toUpperCase() === 'BIF';

export function DirectBonusText() {
  return <div className="bonus-text">
    <h3>LINK BONUS 🇧🇮🇧🇮🇧🇮🇧🇮🇧🇮🇧🇮🇧🇮🇧🇮</h3>
    <p><b>Uko uronka bonus bijyanye n'ingano y'umutahe watanguje</b></p>
    <p>Kwinjira muri Link Bonus kubantu bari Burundi, usabwa umutahe guhera kuri 100.000 BIF kuzamura kugeza kuri 10.000.000 BIF.</p>
    <p>Uhabwa bonus ubwo nyine uhejeje gushyiramo umutahe, uhabwa 5% kumunsi kandi uhabwa inyungu y'iminsi 90 nka welcome bonus.</p>
    <p>Raba lisiti y'imitahe na bonus, hanyuma uhitemo ayo watanguza.</p>
    <ul>
      <li>Iyo utanguje umutahe wa 100.000 BIF, uca uronka bonus ya 450.000 BIF.</li>
      <li>Utanguje umutahe wa 200.000 BIF, uca uronka bonus ya 900.000 BIF.</li>
      <li>Iyo utanguje umutahe wa 300.000 BIF, uca uronka bonus ya 1.350.000 BIF.</li>
      <li>Iyo utanguje umutahe wa 400.000 BIF, uca uronka bonus ya 1.800.000 BIF.</li>
      <li>Iyo utanguje umutahe wa 500.000 BIF, uca uronka bonus ya 2.250.000 BIF.</li>
      <li>Iyo utanguje umutahe wa 600.000 BIF, uca uronka bonus ya 2.700.000 BIF.</li>
      <li>Iyo utanguje umutahe wa 700.000 BIF, uca uronka bonus ya 3.150.000 BIF.</li>
      <li>Iy'utangije umutahe wa 800.000 BIF, uca uronka bonus ya 3.600.000 BIF.</li>
      <li>Iyo utanguje umutahe wa 900.000 BIF, uronka bonus ya 4.050.000 BIF.</li>
    </ul>
    <p>Hanyuma kubantu batanguza umutahe guhera kuri 1.000.000 BIF kuzamura, bahabwa bonus zabo zose nta kimwe gikuwemo. Ahabwa inyungu y'amezi 3 yose ya 10%, bitandukanye nabandi bahabwa 5% ukubye iminsi. Indi nyungu bakayihabwa umunsi kumunsi: kuri 1 Million uronka inyungu ya 9.000.000 FBu ingana n'amezi 3. Direct akimara kwinjira ntakindi kintu usabwa.</p>
    <p>Umuntu utanguza umutahe guhera kuri 1.000.000 BIF aba yemerewe kuba yasaba kuba umu agent wa Company mu gihe abishoboye. Murakoze, ni karibu.</p>
    <p>Twandikire kubundi busobanuro.</p>
  </div>;
}
