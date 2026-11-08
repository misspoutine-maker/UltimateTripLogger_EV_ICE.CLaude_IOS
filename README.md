# Ultimate Trip Logger (iOS) — phase 1

SwiftUI, iOS 15+ (iPhone 8). Suivi GPS, arrêts (recharge/repas/autre), frontières, historique, export CSV.

## Compiler avec Codemagic
1. Mets ce dossier dans un dépôt Git (GitHub) et connecte-le à Codemagic.
2. Workflow `ios-unsigned` (fichier codemagic.yaml) → il génère `UltimateTripLogger.ipa` (non signé).
3. Installe l'IPA sur l'iPhone avec Sideloadly (Windows) ou ton outil habituel.

Si tu as déjà la signature Codemagic configurée, ajoute-la au workflow à la place du build non signé.
