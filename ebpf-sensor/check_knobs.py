import numpy as np, pickle, pandas as pd

ART = "../inference-service/app/artifacts"
cols = pickle.load(open(f"{ART}/feature_cols_clean.pkl", "rb"))
df = pd.DataFrame(np.load(f"{ART}/X_test_sample.npy"), columns=cols)

print("== Knob 1: Init Win default (-1 or 0?) ==")
print("Init Fwd Win  min:", df["Init Fwd Win Bytes"].min(),
      " frac==-1:", round((df["Init Fwd Win Bytes"] == -1).mean(), 3))
print("Init Bwd Win  min:", df["Init Bwd Win Bytes"].min(),
      " frac==-1:", round((df["Init Bwd Win Bytes"] == -1).mean(), 3))

print()
print("== Knob 2: Active/Idle should be mostly zero ==")
for c in ["Active Mean", "Idle Mean", "Active Max", "Idle Max"]:
    print(f"{c:11s} zero-frac:", round((df[c] == 0).mean(), 3))
