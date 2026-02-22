# Politique de Confidentialité pour KintaMed Edge 🛡️

**Dernière mise à jour : 23 janvier 2026**

KintaMed Edge s'engage à protéger la confidentialité et la sécurité des données des patients traitées par les agents de santé communautaires (ASC). Cette politique de confidentialité explique notre philosophie de données « Zéro-Cloud » et comment nous garantissons une confidentialité absolue sur le terrain.

---

## 1. Philosophie des données Zéro-Cloud
KintaMed Edge est une application **prioritairement hors ligne (offline-first)**. **Nous ne collectons, ne transmettons et ne stockons aucune donnée sur des serveurs externes, des fournisseurs cloud ou des bases de données tierces.**

Tout ce que vous saisissez dans l'application reste sur l'appareil physique où l'application est installée.

## 2. Données que nous traitons localement
Pour fournir un soutien à la décision clinique, l'application traite les données suivantes exclusivement sur votre appareil :
- **Données démographiques du patient** : Nom, âge, sexe, date de naissance.
- **Données cliniques** : Signes vitaux (TA, SpO2, fréquence cardiaque, etc.), symptômes et antécédents médicaux.
- **Médias cliniques** : Photos de plaies, d'éruptions cutanées ou images diagnostiques.
- **Enregistrements vocaux** : Traitement audio temporaire pour la conversion parole-texte.

## 3. Sécurité des données et cryptage
Toutes les données stockées sur l'appareil sont protégées par **SQLCipher**, offrant un cryptage de qualité militaire (AES-256). Cela garantit que même si l'appareil physique est perdu ou volé, les informations des patients ne peuvent pas être consultées sans les identifiants autorisés de l'application.

## 4. Autorisations requises
L'application demande des autorisations spécifiques pour fonctionner sur le terrain :
- **Caméra** : Pour capturer des images cliniques pour l'analyse par l'IA.
- **Microphone** : Pour permettre l'enregistrement des symptômes en mode mains libres.
- **Stockage/Système de fichiers** : Pour stocker les poids du modèle AI MedGemma (~3 Go) et la base de données locale cryptée.

## 5. Accès par des tiers
Il n'y a **aucun accès par des tiers** à vos données. Étant donné que l'application ne se connecte pas à Internet pour ses fonctions de base, aucune donnée ne peut être partagée avec des annonceurs, des fournisseurs d'analyses ou des agences gouvernementales.

## 6. Conservation des données
Les données sont conservées sur votre appareil jusqu'à ce que vous supprimiez manuellement une évaluation ou effaciez les données de l'application. Les utilisateurs sont responsables d'effectuer des purges de données périodiques conformément aux protocoles de leur organisation de santé locale.

## 7. Contact
Pour toute question concernant la mise en œuvre technique de cette politique de confidentialité, veuillez contacter l'équipe de développement sur notre dépôt.

---
**Note** : En utilisant KintaMed Edge, vous reconnaissez que vous êtes responsable de la sécurité physique de l'appareil et de la confidentialité de toutes les données des patients affichées à l'écran.
