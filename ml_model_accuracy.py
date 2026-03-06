import pandas as pd
import numpy as np
import joblib

from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.pipeline import make_pipeline

from sklearn.ensemble import RandomForestClassifier
from sklearn.neural_network import MLPClassifier

from xgboost import XGBClassifier


data = pd.read_csv(r"C:\my-data\flutter_apps\aarogya-mitra\backend\data\disease_symptoms.csv")

X = data.drop("disease", axis=1)
y = data["disease"]

label_encoder = LabelEncoder()
y_encoded = label_encoder.fit_transform(y)

X_train, X_test, y_train, y_test = train_test_split(
    X,
    y_encoded,
    test_size=0.2,
    random_state=42
)

rf_model = RandomForestClassifier(
    n_estimators=200,
    random_state=42
)

xgb_model = XGBClassifier(
    n_estimators=200,
    learning_rate=0.1,
    max_depth=6,
    use_label_encoder=False,
    eval_metric="mlogloss"
)

mlp_model = make_pipeline(
    StandardScaler(),
    MLPClassifier(
        hidden_layer_sizes=(128, 64),
        max_iter=500,
        random_state=42
    )
)

print("Training RandomForest...")
rf_model.fit(X_train, y_train)

print("Training XGBoost...")
xgb_model.fit(X_train, y_train)

print("Training MLP...")
mlp_model.fit(X_train, y_train)

rf_pred = rf_model.predict(X_test)
xgb_pred = xgb_model.predict(X_test)
mlp_pred = mlp_model.predict(X_test)

rf_acc = accuracy_score(y_test, rf_pred)
xgb_acc = accuracy_score(y_test, xgb_pred)
mlp_acc = accuracy_score(y_test, mlp_pred)

print("\nIndividual Model Accuracy")
print("--------------------------")
print("RandomForest:", rf_acc)
print("XGBoost:", xgb_acc)
print("MLP:", mlp_acc)

rf_prob = rf_model.predict_proba(X_test)
xgb_prob = xgb_model.predict_proba(X_test)
mlp_prob = mlp_model.predict_proba(X_test)

ensemble_prob = (rf_prob + xgb_prob + mlp_prob) / 3

ensemble_pred = np.argmax(ensemble_prob, axis=1)

ensemble_acc = accuracy_score(y_test, ensemble_pred)

print("\nEnsemble Accuracy")
print("--------------------------")
print("Ensemble Accuracy:", ensemble_acc)

print("\nClassification Report")
print("--------------------------")
print(classification_report(y_test, ensemble_pred))

joblib.dump(rf_model, "rf_model.pkl")
joblib.dump(xgb_model, "xgb_model.pkl")
joblib.dump(mlp_model, "mlp_model.pkl")
joblib.dump(label_encoder, "label_encoder.pkl")

print("\nModels Saved Successfully!")