/**
 * Five model identifiers — match the id strings in /predict response exactly.
 * Colors: lime/cyan/violet/amber are CHART-ONLY categorical colors (not UI chrome).
 * AE is anomaly-only; the four supervised models produce label + confidence votes.
 */
export const MODELS = [
  { id: 'random_forest', label: 'Random Forest', short: 'RF',  color: 'var(--lime)'   },
  { id: 'xgboost',       label: 'XGBoost',       short: 'XGB', color: 'var(--cyan)'   },
  { id: 'lightgbm',      label: 'LightGBM',       short: 'LGB', color: 'var(--violet)' },
  { id: 'cnn_lstm',      label: 'CNN-LSTM',        short: 'CNN', color: 'var(--amber)'  },
  { id: 'autoencoder',   label: 'Autoencoder',     short: 'AE',  color: 'var(--red)'    },
]

export const SUPERVISED = MODELS.filter(m => m.id !== 'autoencoder')
export const AE_MODEL   = MODELS.find(m => m.id === 'autoencoder')

export const AE_THRESHOLD = 0.0726  // 95th-percentile benign reconstruction error — fixed

export function modelById(id) {
  return MODELS.find(m => m.id === id) ?? { id, label: id, short: id, color: 'var(--muted)' }
}
