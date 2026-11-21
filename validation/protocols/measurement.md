# Mesures de faisabilité — protocole de phase 4

Ce protocole prépare les essais ; il ne constitue pas leurs résultats. Conserver les
preuves antérieures et créer un identifiant de run différent pour chaque campagne.
Corpus figé : `assets/corpus/fr_demo.json`, dix textes fr-01 à fr-10. Reporter son
SHA-256, le build, les ressources et leurs versions avant chaque essai.

## Attente et contrôle du cache

Faire cinq essais froids : relancer le processus, moteur déchargé, audio de l'entrée
absent du cache, ressources déjà installées. Ne pas prétendre vider le cache système.
Faire cinq essais chauds : moteur chargé, mais WAV de l'entrée absent du cache.
Faire séparément un cache hit. Consigner les conditions et l'ordre, pas seulement les
médianes. Ne supprimer que les entrées de cache appartenant au banc d'essai.

Utiliser `MeasurementCollector` et son horloge monotone pour début, premier PCM
disponible et événement de démarrage du lecteur. Ce dernier ne mesure pas le premier
son audible : sans mesure indépendante, `firstAudibleSoundUs` reste absent. Ne pas
déclarer ces essais accomplis parce que le collecteur est implémenté.

## Session de vingt minutes

Sur téléphone physique : noter réseau, température si disponible, alimentation USB,
batterie initiale/finale, début/fin, configuration, état des caches. Échantillonner la
mémoire avant, pendant (pic observé) et après ; une mesure manquante reste absente.
Compter séparément bundle, temporaires, cache et espace libéré. Une mesure courte
de batterie ne permet aucune extrapolation d'autonomie.

Mesurer les attentes entre segments au cours de la session ; les WAV concaténés ne
représentent pas ces attentes. Les commandes écran verrouillé, trois appels et trois
déconnexions seront exercés avec US3, pas simulés ici. Les reprises durables et
changements arbitraires de passage attendent US4. Conserver chaque valeur brute et
sa preuve ; une annulation n'est pas une valeur zéro.

## Intelligibilité et accessibilité

Deux évaluateurs francophones remplissent séparément `intelligibility.csv`, sans
voir les notes de l'autre. Notes 1 à 5 ; au moins huit textes >=4 par évaluateur,
sur les dix. Les confirmations qualitatives de phase 3 ne sont pas converties en
notes inventées. Conserver erreurs et divergences.

Pour le bilan : TalkBack au défaut puis au maximum système réel, affichage par
défaut. Vérifier statuts, export, annulation, erreur et retour du focus. Relever
libellés et `font_scale`. La réserve d'US1 ne vaut pas réussite de SC-007.
