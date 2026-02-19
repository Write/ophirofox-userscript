# ophirofox-userscript
Génère automatiquement un userscript à chaque release d'une nouvelle version d'ophirofox


Lien vers le projet : https://github.com/lovasoa/ophirofox

Après le premier chargement d'une page d'article, mais avant l'utilisation du lien, il faut aller modifier la variable de script universityName (Voir https://github.com/lovasoa/ophirofox/blob/master/ophirofox/manifest.json#L851 pour la liste des valeurs). Contrairement à l'ancienne façon de faire, cette opération n'a pas à être refaite à chaque mise à jour du userscript.

# Installation sur iOS 

**1er méthode**  
Télécharger l'extension Safari : [apps.apple.com/fr/app/userscripts/id1463298887](https://apps.apple.com/fr/app/userscripts/id1463298887)  
Puis définir un dossier, et enfin glisser le ophirofox.user.js dedans.

**2nd méthode**  
Une fois l'extension installée, se rendre sur la page "[raw](https://raw.githubusercontent.com/Write/ophirofox-userscript/refs/heads/main/ophirofox.user.js)" puis ouvrir le menu Safari, cliquer sur l'extension, puis "installer".
Il faudra aussi cliquer sur "Toujours autoriser sur chaque site web" lors du premier clic sur l'extension Safari
