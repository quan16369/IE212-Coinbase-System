# MLOps Training Summary

- Model: `coinbase_price_lightgbm`
- Family: `lightgbm_regressor`
- Target: `future_return`
- Horizon: `4`
- Frequency minutes: `60`
- Training rows: `64623`
- Source data: `/workspace/Coinbase_Streaming/data/BTCUSDT_5m_full.csv`

## Metrics

| Metric | Value |
| --- | ---: |
| `mae` | 407.79281 |
| `rmse` | 663.32468 |
| `r2` | 0.99891181 |
| `smape` | 0.0069167139 |
| `direction_accuracy` | 0.50692456 |
| `naive_mae` | 382.10039 |
| `naive_rmse` | 631.57087 |
| `naive_smape` | 0.006532236 |
| `mae_improvement_vs_naive` | -0.067239955 |
| `rmse_improvement_vs_naive` | -0.050277519 |
| `smape_improvement_vs_naive` | -0.058858549 |
| `train_rows` | 51698 |
| `validation_rows` | 12925 |

## Warnings

- mae_improvement_vs_naive is negative (-0.06724); model underperforms the naive baseline.
- rmse_improvement_vs_naive is negative (-0.0502775); model underperforms the naive baseline.
- smape_improvement_vs_naive is negative (-0.0588585); model underperforms the naive baseline.
