import { prescriptionInfo } from '../prescription';

describe('prescriptionInfo', () => {
  const now = new Date(2026, 6, 6); // 06/07/2026

  it('returns null without dcb_em', () => {
    expect(prescriptionInfo({}, now)).toBeNull();
  });

  it('computes lost installments past 60 months', () => {
    const info = prescriptionInfo(
      { dcb_em: '2020-01-15', benefit_monthly_value: '800.0' },
      now
    );
    expect(info.monthsSinceDcb).toBe(77);
    expect(info.lostInstallments).toBe(17);
    expect(info.lostValue).toBe(13600);
    expect(info.monthsToCliff).toBe(0);
  });

  it('reports months to cliff inside the window', () => {
    const info = prescriptionInfo({ dcb_em: '2022-01-06' }, now);
    expect(info.lostInstallments).toBe(0);
    expect(info.monthsToCliff).toBe(6);
    expect(info.lostValue).toBeNull();
  });
});
