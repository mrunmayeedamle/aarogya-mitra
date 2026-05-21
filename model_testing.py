import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from xgboost import XGBClassifier
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix
import numpy as np
from scipy.stats import mode
from sklearn.preprocessing import LabelEncoder

# Paths to your CSV files
train_path = "C:/my-data/flutter_apps/aarogya-mitra/backend/data/Marathi_Training.csv"
test_path = "C:/my-data/flutter_apps/aarogya-mitra/backend/data/Marathi_Testing.csv"

# Load the CSVs
train_df = pd.read_csv(train_path)
test_df = pd.read_csv(test_path)

# Separate features and labels
X_train = train_df.drop("आजार", axis=1)
y_train = train_df["आजार"]

X_test = test_df.drop("आजार", axis=1)
y_test = test_df["आजार"]

# Encode Marathi disease labels to integers
le = LabelEncoder()
y_train_encoded = le.fit_transform(y_train)
y_test_encoded = le.transform(y_test)

# ------------------- Train Models -------------------

# Random Forest
rf = RandomForestClassifier(n_estimators=100, random_state=42)
rf.fit(X_train, y_train_encoded)
y_pred_rf = rf.predict(X_test)
y_pred_rf_labels = le.inverse_transform(y_pred_rf)  # Map back to Marathi

# XGBoost
xgb = XGBClassifier(
    n_estimators=100,
    learning_rate=0.1,
    use_label_encoder=False,
    eval_metric='mlogloss',
    random_state=42
)
xgb.fit(X_train, y_train_encoded)
y_pred_xgb = xgb.predict(X_test)
y_pred_xgb_labels = le.inverse_transform(y_pred_xgb)

# MLP
mlp = MLPClassifier(hidden_layer_sizes=(100,), max_iter=500, random_state=42)
mlp.fit(X_train, y_train_encoded)
y_pred_mlp = mlp.predict(X_test)
y_pred_mlp_labels = le.inverse_transform(y_pred_mlp)

# ------------------- Evaluation Function -------------------
def evaluate_model(y_true, y_pred, model_name):
    print(f"--- {model_name} ---")
    print("Accuracy:", accuracy_score(y_true, y_pred))
    print("Precision:", precision_score(y_true, y_pred, average='weighted'))
    print("Recall:", recall_score(y_true, y_pred, average='weighted'))
    print("F1 Score:", f1_score(y_true, y_pred, average='weighted'))
    print("Confusion Matrix:\n", confusion_matrix(y_true, y_pred))
    print("\n")

# Evaluate individual models
evaluate_model(y_test, y_pred_rf_labels, "Random Forest")
evaluate_model(y_test, y_pred_xgb_labels, "XGBoost")
evaluate_model(y_test, y_pred_mlp_labels, "MLP")

# ------------------- Ensemble -------------------
# Combine predictions
all_preds = np.array([y_pred_rf, y_pred_xgb, y_pred_mlp])

# Majority vote
y_pred_ensemble = mode(all_preds, axis=0).mode.flatten()  # flatten ensures 1D array

# Map back to Marathi labels
y_pred_ensemble_labels = le.inverse_transform(y_pred_ensemble)

# Evaluate ensemble
evaluate_model(y_test, y_pred_ensemble_labels, "Ensemble")