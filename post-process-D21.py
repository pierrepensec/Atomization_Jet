import pandas as pd
import matplotlib.pyplot as plt

fichiers = [
    "donnees_D21_run-L8-np3-ue0.001.txt",
    "donnees_D21_run-L8-np3-ue0.1.txt",
    "donnees_D21_run-L9-np3-ue0.001.txt",
    "donnees_D21_run-L9-np3-ue0.1.txt",
    "donnees_D21_run-L10-np3-ue0.001.txt",
    "donnees_D21_run-L10-np3-ue0.1.txt"
]

plt.figure(figsize=(10, 6))

for f in fichiers:
    # Lecture avec espaces comme séparateurs
    df = pd.read_csv(f, delim_whitespace=True, header=None, names=["t", "aire", "perimetre"])
    
    # Filtrage temporel et prévention des divisions par zéro
    df = df[df["t"] <= 3.48]
    df = df[df["perimetre"] > 0]
    
    # Calcul du D21 et de sa moyenne
    df["D21"] = 4 * (df["aire"] / df["perimetre"])
    moyenne = df["D21"].mean()
    
    # Tracé
    nom_courbe = f.replace("donnees_D21_", "").replace(".txt", "")
    plt.plot(df["t"], df["D21"], label=f"{nom_courbe} (Moy: {moyenne:.4f})")

plt.xlabel("Physical time (s)")
plt.ylabel("D21")
plt.title("Sauter Diameter in function of time")
plt.xlim(0, 3.48)
plt.grid(True, linestyle='--', alpha=0.7)
plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
plt.tight_layout()
plt.show()