export const PRESCRIPTION_WINDOW_MONTHS = 60;

export function prescriptionInfo(lead, now = new Date()) {
  if (!lead?.dcb_em) return null;
  const dcb = new Date(`${lead.dcb_em}T00:00:00`);
  let months =
    (now.getFullYear() - dcb.getFullYear()) * 12 +
    (now.getMonth() - dcb.getMonth());
  if (now.getDate() < dcb.getDate()) months -= 1;
  if (months < 0) months = 0;
  const lost = Math.max(months - PRESCRIPTION_WINDOW_MONTHS, 0);
  const monthly = Number(lead.benefit_monthly_value) || null;
  return {
    monthsSinceDcb: months,
    lostInstallments: lost,
    monthlyValue: monthly,
    lostValue: monthly ? monthly * lost : null,
    monthsToCliff: Math.max(PRESCRIPTION_WINDOW_MONTHS - months, 0),
  };
}
