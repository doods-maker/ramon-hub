import { formatBrl } from './currency';

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

// Prescrição já calculada pela API (Lead#prescription: snake_case) nas frases
// do chip do painel/funil: "N parcelas já prescritas · prescrevendo R$ X/mês"
// ou "prescreve em N meses" (só quando a API manda months_to_cliff).
export function prescriptionText(t, prescription, monthly) {
  if (!prescription) return null;
  const lost = prescription.lost_installments;
  if (lost > 0) {
    const partes = [t('RAMON.KANBAN.CARD.PRESCRIPTION_LOST', { count: lost })];
    if (Number(monthly))
      partes.push(
        t('RAMON.KANBAN.CARD.PRESCRIPTION_BLEEDING', {
          value: formatBrl(monthly),
        })
      );
    return partes.join(' · ');
  }
  const months = prescription.months_to_cliff;
  if (months == null) return null;
  return t('RAMON.KANBAN.CARD.PRESCRIPTION_SOON', { months }, months);
}

// Frase do chip do card do funil e do painel do lead, a partir do
// prescriptionInfo: "prescrevendo R$ X/mês" (sangrando com valor), "N parcelas
// já prescritas" (sangrando sem valor) ou "prescreve em N meses" (até
// `soonMonths`; o Radar passa Infinity). bleeding = tom ruby, senão âmbar.
export function prescriptionChip(t, p, soonMonths = 6) {
  if (!p) return null;
  if (p.lostInstallments > 0)
    return {
      bleeding: true,
      text: p.monthlyValue
        ? t('RAMON.KANBAN.CARD.PRESCRIPTION_BLEEDING', {
            value: formatBrl(p.monthlyValue),
          })
        : t('RAMON.KANBAN.CARD.PRESCRIPTION_LOST', {
            count: p.lostInstallments,
          }),
    };
  if (p.monthsToCliff > soonMonths) return null;
  return {
    bleeding: false,
    text: t(
      'RAMON.KANBAN.CARD.PRESCRIPTION_SOON',
      { months: p.monthsToCliff },
      p.monthsToCliff
    ),
  };
}
