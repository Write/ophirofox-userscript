# ophirofox-userscript
Génère automatiquement un userscript à chaque release d'une nouvelle version d'ophirofox


Lien vers le projet : https://github.com/lovasoa/ophirofox


Après le premier chargement d'une page d'article, un popup vous demande de choisir votre université dans la liste.
Pour changer ensuite, deux options :

1. Menu de l’extension (icône dans la barre)
   - clic sur le script
   - « Changer l’université »

2. Console JS (F12), sur un site ou le script est actif :
   - `setUniversityName("Mon université")`
   - ou `setUniversityName("")` pour réinitialiser
   - puis rechargez la page

Voir la liste des universités disponibles ici : https://github.com/lovasoa/ophirofox/blob/8c0105344e5bdbbfea6288a956c849876e886c3b/ophirofox/manifest.json#L898

# Installation sur iOS 

**1er méthode**  
Télécharger l'extension Safari : [apps.apple.com/fr/app/userscripts/id1463298887](https://apps.apple.com/fr/app/userscripts/id1463298887)  
Puis définir un dossier, et enfin glisser le ophirofox.user.js dedans.

**2nd méthode**  
Une fois l'extension installée, se rendre sur la page "[raw](https://raw.githubusercontent.com/Write/ophirofox-userscript/refs/heads/main/ophirofox.user.js)" puis ouvrir le menu Safari, cliquer sur l'extension, puis "installer".
Il faudra aussi cliquer sur "Toujours autoriser sur chaque site web" lors du premier clic sur l'extension Safari
