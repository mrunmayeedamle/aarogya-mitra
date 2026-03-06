import pandas as pd
import numpy as np
import joblib
import os
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
from sklearn.preprocessing import LabelEncoder

def test_ensemble_accuracy():
    print("🧪 Starting Model Accuracy Test...\n")

    data_path = 'data/disease_symptoms.csv'
    model_dir = 'model'

    if not os.path.exists(data_path):
        print(f"❌ Data file not found at {data_path}")
        return

    try:
        df = pd.read_csv(data_path, encoding='utf-8')
        X = df.iloc[:, 1:].fillna(0).astype(int)
        y = df.iloc[:, 0].astype(str)

        # Load or fit LabelEncoder
        le_path = os.path.join(model_dir, 'label_encoder.pkl')
        if os.path.exists(le_path):
            le = joblib.load(le_path)
            print("✅ Label Encoder loaded.")
        else:
            le = LabelEncoder()
            le.fit(y)
            print("⚠️ Label Encoder not found, fitted new one from data.")

        y_encoded = le.transform(y)

        _, X_test, _, y_test = train_test_split(
            X, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
        )

        print(f"📊 Testing on {len(X_test)} samples (20% of dataset)")

        rf = joblib.load(os.path.join(model_dir, 'rf_model.pkl'))
        xgb = joblib.load(os.path.join(model_dir, 'xgb_model.pkl'))
        mlp = joblib.load(os.path.join(model_dir, 'mlp_model.pkl'))
        print("✅ All models loaded successfully.")


        y_pred_rf = rf.predict(X_test)
        y_pred_xgb = xgb.predict(X_test)
        y_pred_mlp = mlp.predict(X_test)

        acc_rf = accuracy_score(y_test, y_pred_rf)
        acc_xgb = accuracy_score(y_test, y_pred_xgb)
        acc_mlp = accuracy_score(y_test, y_pred_mlp)

        probs_rf = rf.predict_proba(X_test)
        probs_xgb = xgb.predict_proba(X_test)
        probs_mlp = mlp.predict_proba(X_test)

        # Weighted average matching app.py logic
        final_probs = (0.4 * probs_rf + 0.4 * probs_xgb + 0.2 * probs_mlp)
        y_pred_ensemble = np.argmax(final_probs, axis=1)

        acc_ensemble = accuracy_score(y_test, y_pred_ensemble)

        # 7. Print Summary Results
        print("\n" + "="*40)
        print(f"{'MODEL':<25} | {'ACCURACY':<10}")
        print("-" * 40)
        print(f"{'Random Forest':<25} | {acc_rf:.4f}")
        print(f"{'XGBoost':<25} | {acc_xgb:.4f}")
        print(f"{'MLP (Neural Network)':<25} | {acc_mlp:.4f}")
        print("-" * 40)
        print(f"{'⭐ ENSEMBLE (Weighted)':<25} | {acc_ensemble:.4f}")
        print("="*40)

        # 8. Detailed Report for Ensemble
        print("\n📄 Detailed Classification Report (Ensemble):")
        print(classification_report(y_test, y_pred_ensemble, target_names=le.classes_))

    except Exception as e:
        print(f"❌ An error occurred: {e}")

if __name__ == "__main__":
    # Ensure we are in the backend directory context
    test_ensemble_accuracy()
