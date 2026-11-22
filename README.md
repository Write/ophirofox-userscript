# ophirofox-userscript

Userscript généré automatiquement (toutes les 2 h par GitHub Actions) à partir de la
release `current` du projet [lovasoa/ophirofox](https://github.com/lovasoa/ophirofox) :
il ajoute un bouton **« Lire sur Europresse »** sur les articles de presse, et ouvre
l'article via l'accès distant de votre bibliothèque / université.

- Userscript prêt à installer : [`ophirofox.user.js`](https://raw.githubusercontent.com/Write/ophirofox-userscript/refs/heads/main/ophirofox.user.js)
- Un partenariat manquant ou une URL cassée ? → ça se corrige en amont, dans
  [lovasoa/ophirofox](https://github.com/lovasoa/ophirofox) (pas dans ce dépôt, qui ne fait que générer le fichier).

---

## Installation

### iOS / iPadOS (Safari)

1. Installer l'extension Safari **Userscripts** :
   [apps.apple.com/fr/app/userscripts/id1463298887](https://apps.apple.com/fr/app/userscripts/id1463298887)
2. L'activer : **Réglages → Safari → Extensions → Userscripts**, puis choisir un dossier
   de stockage pour les scripts (par ex. un dossier dans Fichiers ou iCloud Drive).
3. Installer le script, au choix :
   - **depuis Safari** : ouvrir la page
     [raw](https://raw.githubusercontent.com/Write/ophirofox-userscript/refs/heads/main/ophirofox.user.js),
     toucher le bouton de l'extension dans la barre d'adresse, puis **« Installer »** ;
   - **manuellement** : télécharger `ophirofox.user.js` et le glisser dans le dossier choisi
     à l'étape 2 (app Fichiers).
4. Au premier usage de l'extension sur un site, iOS demande l'autorisation :
   choisir **« Toujours autoriser sur ce site web »** (à faire pour chaque site utilisé,
   et de préférence pour `europresse.com` et `*.idm.oclc.org` / votre proxy).

### macOS (Safari)

Identique à iOS : même extension **Userscripts** (version macOS), même page `raw`, même
dossier de stockage.

### Autres navigateurs (Firefox, Chrome, Edge, Brave…)

Installer [Tampermonkey](https://www.tampermonkey.net/) ou
[Violentmonkey](https://violentmonkey.github.io/), puis ouvrir la page `raw` ci-dessus :
le gestionnaire propose l'installation.

---

## Configuration

**Au premier chargement d'une page Europresse**, un panneau **« Paramètres Ophirofox »**
s'ouvre automatiquement :

- champ de **recherche** + liste des partenaires (bibliothèques, universités, « Pas d'intermédiaire »…) ;
- **Ouvrir les liens Europresse dans un nouvel onglet** ;
- **Ouvrir automatiquement le lien lorsqu'un seul résultat est trouvé**.

Valider avec **Enregistrer**. Les réglages sont stockés comme valeurs du userscript
(`GM.setValue`), donc **ils survivent aux mises à jour du script** : plus besoin de
rééditer le fichier à chaque nouvelle version.

### Changer de partenaire (ou d'options) ensuite

Trois moyens, selon la plateforme :

| Plateforme | Méthode |
|---|---|
| **iOS / iPadOS / macOS (Safari, extension Userscripts)** | Bouton **⚙** affiché **juste à côté du lien « Lire sur Europresse »** → rouvre le panneau Paramètres |
| **Tampermonkey / Violentmonkey (Firefox, Chrome, Edge…)** | **Menu du gestionnaire de userscripts** (icône de l'extension dans la barre d'outils) → cliquer sur le script → **« Paramètres Ophirofox »** |
| N'importe où, en dernier recours | Console JS (F12), sur une page où le script est actif : `setUniversityName("Mon université")`, ou `setUniversityName("")` pour tout réinitialiser, puis recharger la page |

Pourquoi deux interfaces ? L'extension **Userscripts** (Apple) n'expose pas les commandes
de menu (`GM.registerMenuCommand`) : c'est pour ça que le bouton **⚙** n'apparaît que sur
iPhone / iPad / Mac, accolé au lien Europresse. Ailleurs, le menu du gestionnaire fait le
travail et le bouton ⚙ est inutile (il n'est donc pas affiché).

### Liste des partenaires disponibles

147 entrées, définies dans le manifeste d'ophirofox :
[`ophirofox/manifest.json`](https://github.com/lovasoa/ophirofox/blob/master/ophirofox/manifest.json)
→ objet `browser_specific_settings.ophirofox_metadata.partners`.
Le plus simple reste le champ de recherche du panneau Paramètres.

---

## Mise à jour

Le workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) vérifie toutes les 2 h
la release `current` d'ophirofox, régénère `ophirofox.user.js` et publie un tag
(`vX.Y.Z.W`) quand la version change.

- **Mise à jour du script** : réinstaller depuis la page `raw` (sur iOS, la fonction
  « mise à jour » de l'app Userscripts refait la même chose), ou laisser le gestionnaire
  de userscripts vérifier les mises à jour.
- **Vos réglages ne sont pas perdus** : ils ne sont pas dans le fichier, mais dans le
  stockage du gestionnaire.

---

## Dépannage

- **Aucun bouton / rien ne se passe** : l'extension n'est pas autorisée sur ce site
  (Safari → menu de l'extension → « Toujours autoriser sur ce site web »).
- **Le panneau Paramètres revient à chaque page** : le gestionnaire ne supporte pas
  `GM.setValue` (utiliser Tampermonkey / Violentmonkey / Userscripts à jour).
- **Le lien mène à une page d'erreur du proxy** : le partenariat est obsolète ou l'URL a
  changé → à signaler/corriger dans
  [lovasoa/ophirofox](https://github.com/lovasoa/ophirofox).
- **Bouton ⚙ absent sur desktop** : normal, il est réservé aux plateformes Apple ; passer
  par le menu du gestionnaire.
