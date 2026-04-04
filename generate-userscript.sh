#!/bin/bash

USERSCRIPT="./ophirofox.user.js"
MANIFEST="./ophirofox/manifest.json"

json_data=$(jq -rc '.content_scripts[] ' "$MANIFEST")
partners=$(jq -rc '.browser_specific_settings.ophirofox_metadata.partners' "$MANIFEST")
europress_urls=$(jq -rc 'del(.optional_permissions[] | select(. == "webNavigation"))' "$MANIFEST" | jq -rc '.optional_permissions[]')
europress_urls_count=$(jq -rc 'del(.optional_permissions[] | select(. == "webNavigation"))' "$MANIFEST" | jq -rc '.optional_permissions[]' | wc -l)

indent() {
  local indentSize=2
  local indent=1
  if [ -n "$1" ]; then indent=$1; fi
  pr -to $(($indent * $indentSize))
}

# ---- Blocs JS extraits en heredoc pour éviter les problèmes d'échappement ----

read -r -d '' PICKER_BLOCK << 'JSBLOCK'
  function showUniversityPicker() {
      return new Promise((resolve) => {
          const overlay = document.createElement('div');
          overlay.style.cssText = `
              position: fixed; inset: 0; z-index: 2147483647;
              background: rgba(0,0,0,0.7);
              display: flex; align-items: center; justify-content: center;
              font-family: sans-serif;
          `;
          const box = document.createElement('div');
          box.style.cssText = `
              background: #fff; border-radius: 10px; padding: 24px;
              max-width: 480px; width: 90%; box-shadow: 0 8px 32px rgba(0,0,0,0.3);
          `;
          const title = document.createElement('h2');
          title.textContent = 'Choisissez votre universite';
          title.style.cssText = 'margin: 0 0 8px; font-size: 18px; color: #222;';
          const subtitle = document.createElement('p');
          subtitle.textContent = 'Ce choix sera sauvegarde. Vous pourrez le modifier via le menu de l\'extension.';
          subtitle.style.cssText = 'margin: 0 0 16px; font-size: 13px; color: #666;';
          const select = document.createElement('select');
          select.style.cssText = `
              width: 100%; padding: 8px; font-size: 14px;
              border: 1px solid #ccc; border-radius: 6px;
              margin-bottom: 16px; box-sizing: border-box;
          `;
          ophirofox_config_list.forEach((uni, i) => {
              const opt = document.createElement('option');
              opt.value = i;
              opt.textContent = uni.name;
              select.appendChild(opt);
          });
          const btn = document.createElement('button');
          btn.textContent = 'Confirmer';
          btn.style.cssText = `
              width: 100%; padding: 10px; font-size: 15px; font-weight: bold;
              background: #1a73e8; color: #fff; border: none;
              border-radius: 6px; cursor: pointer;
          `;
          btn.addEventListener('click', async () => {
              const chosen = ophirofox_config_list[parseInt(select.value)];
              await GM.setValue("universityName", chosen.name);
              overlay.remove();
              resolve(chosen.name);
          });
          box.append(title, subtitle, select, btn);
          overlay.appendChild(box);
          document.documentElement.appendChild(overlay);
      });
  }
JSBLOCK

read -r -d '' UNSAFEWINDOW_BLOCK << 'JSBLOCK'
  try {
      unsafeWindow.setUniversityName = async (name) => {
          if (name === undefined) {
              console.error("Usage: setUniversityName(nom) ou setUniversityName('') pour reinitialiser");
              return;
          }
          if (name === "") {
              await GM.setValue("universityName", null);
              console.log("Reinitialise — rechargez la page, le picker reapparaitra.");
              return;
          }
          const found = ophirofox_config_list.find(u => u.name === name);
          if (!found) {
              console.error("Universite introuvable dans la liste");
              return;
          }
          await GM.setValue("universityName", found.name);
          console.log("Sauvegarde : " + found.name + " — rechargez la page.");
      };
  } catch(e) {}
JSBLOCK

read -r -d '' CONFIG_FUNCTIONS_BLOCK << 'JSBLOCK'
  function getOphirofoxConfigByName(search_name) {
      return ophirofox_config_list.find(({ name }) => search_name === name);
  }

  const DEFAULT_SETTINGS = {
      partner_name: "Pas d'intermédiaire",
  };

  let current_settings = DEFAULT_SETTINGS;

  async function getOphirofoxConfig() {
      try {
          const partner_name = universityName;
          const name_match = getOphirofoxConfigByName(partner_name);
          if (name_match) return name_match;
      } catch (err) {
          console.warn("No ophirofox domain found: " + err);
      }
      return ophirofox_config_list[0];
  }

  const ophirofox_config = getOphirofoxConfig();

  async function setKeywords(keywords, publishedTime) {
      await GM.setValue("ophirofox_keywords", keywords);
      await GM.setValue("ophirofox_published_time", publishedTime);
  }

  async function ophirofoxEuropresseLink(keywords, { publishedTime } = {}) {
      keywords = keywords ? keywords.trim() : document.querySelector("h1").textContent;
      publishedTime = publishedTime || document.querySelector(
          "meta[property='article:published_time'], meta[property='og:article:published_time'], meta[property='date:published_time']"
      )?.getAttribute("content") || '';
      const a = document.createElement("a");
      a.textContent = "Lire sur Europresse";
      a.className = "ophirofox-europresse";
      a.onmousedown = setKeywords(keywords, publishedTime);
      a.onclick = async function(evt) {
          evt.preventDefault();
          await Promise.resolve([ophirofox_config, setKeywords(keywords, publishedTime)]);
          const obj = await ophirofox_config;
          window.location = obj.AUTH_URL;
      }
      ophirofox_config.then(({ AUTH_URL }) => {
          a.href = AUTH_URL;
      });
      return a;
  }
JSBLOCK

read -r -d '' EUROPRESS_BLOCK << 'JSBLOCK'
      function removeMarkElements() {
          Array.from(document.querySelectorAll("article mark")).forEach(mark => {
              const repl = document.createElement("span");
              repl.className = "mark";
              Array.from(mark.childNodes).forEach(repl.appendChild.bind(repl));
              mark.parentNode.replaceChild(repl, mark);
          });
      }

      async function consumeReadRequest() {
          const keywords = await GM.getValue("ophirofox_keywords");
          const published_time = await GM.getValue("ophirofox_published_time");
          const readRequest = { keywords, published_time };
          await GM.deleteValue("ophirofox_keywords");
          await GM.deleteValue("ophirofox_published_time");
          return readRequest;
      }

      async function hasConsumable() {
          try {
              const requestType = await GM.getValue("ophirofox_request_type");
              const keywords = await GM.getValue("ophirofox_keywords");
              return requestType !== undefined || keywords !== undefined;
          } catch (error) {
              console.error("Erreur lors de la verification des consommables:", error);
              return false;
          }
      }

      async function onLoad() {
          ophirofoxRealoadOnExpired();
          const path = window.location.pathname;
          if (!(
              path.startsWith("/Search/Reading") ||
              path.startsWith("/Search/Advanced") ||
              path.startsWith("/Search/AdvancedMobile") ||
              path.startsWith("/Search/Express") ||
              path.startsWith("/Search/Simple") ||
              path.startsWith("/Search/Result") ||
              path.startsWith("/Search/ResultMobile") ||
              path === "/Pdf"
          )) return;

          if (path === '/Pdf' && await hasConsumable()) {
              window.location.pathname = '/Search/Reading';
              return;
          }

          const readRequest = await consumeReadRequest();
          const search_terms = readRequest.keywords;
          const published_time = readRequest.published_time;

          if (!search_terms) return;
          const stopwords = new Set(['d', 'l', 'et', 'sans', 'or']);
          const keywords = search_terms
              .replace(/œ/g, 'oe')
              .split(/[^\p{L}]+/u)
              .filter(w => !stopwords.has(w))
              .join(' ');

          const keyword_field_id = path.startsWith("/Search/Result") ? "NativeQuery" : "Keywords";

          onElemAvailable('#' + keyword_field_id).then((selector) => {
              selector.value = 'TIT_HEAD=' + keywords;
              selector.form.submit();
          });

          onElemAvailable('#DateFilter_DateRange').then((selector) => {
              if (selector) {
                  if (!published_time) {
                      selector.value = 9;
                  } else {
                      const publishedDate = new Date(published_time);
                      publishedDate.setUTCHours(0, 0, 0, 0);
                      const currentDate = new Date();
                      const timeDifference = currentDate.getTime() - publishedDate.getTime();
                      const daysDifference = Math.ceil(timeDifference / (1000 * 60 * 60 * 24));
                      let filterValue = 9;
                      switch (true) {
                          case (daysDifference <= 1): filterValue = 2; break;
                          case (daysDifference <= 3): filterValue = 11; break;
                          case (daysDifference <= 7): filterValue = 3; break;
                          case (daysDifference <= 30): filterValue = 4; break;
                          case (daysDifference <= 90): filterValue = 5; break;
                          case (daysDifference <= 180): filterValue = 6; break;
                          case (daysDifference <= 365): filterValue = 7; break;
                          case (daysDifference <= 730): filterValue = 8; break;
                          default: filterValue = 9; break;
                      }
                      selector.value = filterValue;
                  }
              }
          });
      }

      function ophirofoxRealoadOnExpired() {
          const params = new URLSearchParams(window.location.search);
          if (params.get("ErrorCode") == "4000112") {
              window.history.back();
          }
      }

      onLoad().catch(console.error);
JSBLOCK

# ---- Construction du header ----

SCRIPT=$(cat <<-END
// ==UserScript==
// @version $1
// @author  Write
// @name    OphirofoxScript
// @grant   GM.getValue
// @grant   GM.setValue
// @grant   GM.deleteValue
// @grant   GM.registerMenuCommand
// @grant   unsafeWindow
// @include https://nouveau.europresse.com/*
END
)
SCRIPT+=$'\n'

while IFS= read -r europress_single_url; do
  SCRIPT+="// @include $europress_single_url"$'\n'
done <<< "$europress_urls"

while IFS= read -r line; do
  matches=$(echo "$line" | jq -r '.matches[]')
  while IFS= read -r matches; do
      SCRIPT+="// @include $matches"$'\n'
  done <<< "$matches"
done <<< "$json_data"

echo "$SCRIPT" > "$USERSCRIPT"

SCRIPT+='//
// @run-at      document-start
//
// ==/UserScript==

/*
 * ╔══════════════════════════════════════════════════════╗
 * ║                   CONFIGURATION                      ║
 * ╠══════════════════════════════════════════════════════╣
 * ║  Au premier lancement, un popup vous demande de      ║
 * ║  choisir votre universite dans la liste.             ║
 * ║                                                      ║
 * ║  Pour changer ensuite, deux options :                ║
 * ║                                                      ║
 * ║  1. Menu de l'"'"'extension (icone dans la barre)   ║
 * ║     → clic sur le script                             ║
 * ║     → "Changer l'"'"'universite"                    ║
 * ║                                                      ║
 * ║  2. Console JS (F12), sur un site ou le script       ║
 * ║     est actif :                                      ║
 * ║     setUniversityName("Mon universite")              ║
 * ║     ou setUniversityName("") pour reinitialiser      ║
 * ║     puis rechargez la page                           ║
 * ╚══════════════════════════════════════════════════════╝
 */

(async function () {
'"'"'use strict'"'"';

  /* ----------------
   *   HELPERS
   * ---------------- */

  const current = window.location.href;
  const hostname = window.location.hostname;

  function match(str, rule) {
      var domainRule = rule.replace(/^https?:\/\//, '"'"''"'"').replace(/\/\*$/, '"'"''"'"');
      var regexPattern = "^" + domainRule.split('"'"'*'"'"').map(function(part) {
          return part.replace(/([.*+?^=!:${}()|\[\]\/\\])/g, "\\$1");
      }).join('"'"'.*'"'"') + "$";
      var regex = new RegExp(regexPattern);
      return regex.test(str);
  }

  function pasteStyle(str) {
      var node = document.createElement('"'"'style'"'"');
      node.type = '"'"'text/css'"'"';
      node.appendChild(document.createTextNode(str.replace(/;/g, '"'"' !important;'"'"')));
      (document.head ?? document.documentElement).appendChild(node);
  }

  const onElemAvailable = async selector => {
      while (document.querySelector(selector) === null) {
          await new Promise(resolve => requestAnimationFrame(resolve));
      }
      return document.querySelector(selector);
  };

  /* ----------------
   *   CONFIG
   * ---------------- */
'

SCRIPT+="  const ophirofox_config_list = ${partners};"$'\n'
SCRIPT+="$PICKER_BLOCK"
SCRIPT+='
  let universityName = await GM.getValue("universityName", null);
  if (universityName === null) {
      universityName = await showUniversityPicker();
  }

  GM.registerMenuCommand("Changer l'"'"'universite", async () => {
      universityName = await showUniversityPicker();
      location.reload();
  });

'


SCRIPT+="$UNSAFEWINDOW_BLOCK"
SCRIPT+="$CONFIG_FUNCTIONS_BLOCK"

# ---- Bloc europresse ----

SCRIPT+=$'\nif ('
counter=1
while IFS= read -r europress_single_url; do
  if [[ "$counter" -eq "$europress_urls_count" ]]; then
      SCRIPT+=$'\n  match(hostname, "'"$europress_single_url"'")) {'
  else
      SCRIPT+=$'\n  match(hostname, "'"$europress_single_url"'") ||'
  fi
  ((counter++))
done <<< "$europress_urls"

SCRIPT+=$'\n'
SCRIPT+="$EUROPRESS_BLOCK"

css_europress_str=$(command cat ./ophirofox/content_scripts/europresse_article.css | indent 4)
SCRIPT+='
      pasteStyle(`
'"$css_europress_str"'
      `);
  }'

# ---- Boucle content_scripts ----

while IFS= read -r line; do
  matches=$(echo "$line" | jq -r '.matches[]')
  js_files=$(echo "$line" | jq -r '.js[]')
  if jq -e '.css' <<< "$line" > /dev/null; then
    css_files=$(echo "$line" | jq -r '.css[]')
  else
    css_files=""
  fi

  while IFS= read -r matches; do
    if [[ $matches != *"config.js" ]]; then
      while IFS= read -r js_file; do
        if [[ $js_file != *"config.js" ]]; then
          js_str=$(cat ./ophirofox/"$js_file")
        fi
      done <<< "$js_files"

      if [ -n "$css_files" ]; then
          css_str=$(command cat ./ophirofox/"$css_files" | indent 4)
      fi

      SCRIPT+='
  if (match(hostname, "'"$matches"'")) {
      window.addEventListener("load", function(event) {
      '"$js_str"'
      });
      pasteStyle(`
'"$css_str"'
        `);
  }'
    fi
  done <<< "$matches"
done <<< "$json_data"

SCRIPT+='
})();'

echo "$SCRIPT"
echo "$SCRIPT" > "$USERSCRIPT"  # Parse JSON using jq
  matches=$(echo "$line" | jq -r '.matches[]')
  # Iterate through each JS file entry
  while IFS= read -r matches; do
      SCRIPT+="// @include $matches"$'\n'
      #echo " appejnd - $matches"
  done <<< "$matches"
done <<< "$json_data"

echo "$SCRIPT" > "$USERSCRIPT"

SCRIPT+=$'//
// @run-at      document-start
//
// ==/UserScript==
(function () {
'\''use strict'\'';

  /* ----------------
   *   HELPERS
   * ----------------
   * */

  if (! (GM_getValue("universityName",null))) {
    GM_setValue("universityName", "Bibliotheque nationale et universitaire de Strasbourg");
  }

  const universityName = GM_getValue("universityName");

  const current = window.location.href;
  const hostname = window.location.hostname;

  function match(str, rule) {
      // Extract domain pattern from the rule (ignore https:// and /*)
      var domainRule = rule.replace(/^https?:\/\//, '\'''\'').replace(/\/\*$/, '\'''\'');
      
      // Convert the wildcard pattern to a proper regex
      var regexPattern = "^" + domainRule.split('\''*'\'').map(function(part) {
          // Escape special regex characters in each part
          return part.replace(/([.*+?^=!:${}()|\[\]\/\\])/g, "\\$1");
      }).join('\''.*'\'') + "$";
  
      // Create and test the regex against the input string
      var regex = new RegExp(regexPattern);
      return regex.test(str);
  }

  function pasteStyle(str) {
      var node = document.createElement('\''style'\'');
      node.type = '\''text/css'\'';
      node.appendChild(document.createTextNode(str.replace(/;/g, '\'' !important;'\'')));
      if (document.head !== null) {
          document.head.appendChild(node);
      }
      else {
          document.documentElement.appendChild(node);
      }
  }

  const onElemAvailable = async selector => {
        while (document.querySelector(selector) === null) {
            await new Promise(resolve => requestAnimationFrame(resolve));
        }
        return document.querySelector(selector);
  };

  /* ----------------
   *   CODE
   * ----------------
   * */

  const ophirofox_config_list = '"$partners"';

  function getOphirofoxConfigByName(search_name) {
      return ophirofox_config_list.find(({ name }) => search_name === name);
  }

  const DEFAULT_SETTINGS = {
      partner_name: "Pas d'\''intermédiaire",
  };

  let current_settings = DEFAULT_SETTINGS;

  async function getOphirofoxConfig() {
    const url = new URL(window.location);
    try {
      const partner_name = universityName;
      const name_match = getOphirofoxConfigByName(partner_name);
      if (name_match) return name_match;
    } catch (err) {
      console.warn(
        `No ophirofox domain found, using the default ${fallback.name}: ${err}`
      );
    }
    const fallback = ophirofox_config_list[0];
    return fallback;
  }

  const ophirofox_config = getOphirofoxConfig();

  async function setKeywords(keywords, publishedTime) {
      await GM.setValue("ophirofox_keywords", keywords);
      await GM.setValue("ophirofox_published_time", publishedTime);
  }

  /**
   * Crée un lien vers Europresse avec les keywords donnés
   * @param {string} keywords
   * @returns {Promise<HTMLAnchorElement>}
   */
  async function ophirofoxEuropresseLink(keywords, { publishedTime } = {}) {
      // Keywords is the article name
      keywords = keywords ? keywords.trim() : document.querySelector("h1").textContent;
      // Trying to determine published time with meta tags (Open Graph values)
      publishedTime = publishedTime || document.querySelector( "meta[property='\''article:published_time'\''], meta[property='\''og:article:published_time'\''], meta[property='\''date:published_time'\'']")
      ?.getAttribute("content") || '\'''\'';
      // Creating HTML anchor element
      const a = document.createElement("a");
      a.textContent = "Lire sur Europresse";
      a.className = "ophirofox-europresse";
      a.onmousedown = setKeywords(keywords, publishedTime);
      a.onclick = async function(evt) {
          evt.preventDefault();
          await Promise.resolve([ophirofox_config, setKeywords(keywords, publishedTime)])
          const obj = await ophirofox_config;
          window.location = obj.AUTH_URL;
      }
      ophirofox_config.then(({
          AUTH_URL
      }) => {
          a.href = AUTH_URL
      });
      return a;
  }

'

SCRIPT+=$'if ('
counter=1
while IFS= read -r europress_single_url; do

  if [[ "$counter" -eq "$europress_urls_count" ]]; then
      # last element, close the parenthesis.
        SCRIPT+=$'
  match(hostname, "'"$europress_single_url"'")) {'
  else
        SCRIPT+=$'
  match(hostname, "'"$europress_single_url"'") ||'
  fi
  ((counter++))
done <<< "$europress_urls"

# Inject europress_article.{css,js..}
#  js_europress_article_str=$(cat ./ophirofox/content_scripts/europresse_article.js)
# js_europress_search_str=$(cat ./ophirofox/content_scripts/europresse_search.js)
  css_europress_str=$(command cat ./ophirofox/content_scripts/europresse_article.css | indent 4)
  SCRIPT+=$'

      function removeMarkElements() {
          // Remove all the <mark> elements, but keep their contents
          Array.from(document.querySelectorAll("article mark")).forEach(mark => {
              const repl = document.createElement("span");
              repl.className = "mark";
              Array.from(mark.childNodes).forEach(repl.appendChild.bind(repl));
              mark.parentNode.replaceChild(repl, mark);
          });
      }

      // Remove <mark> elements each time the page is updated 
      /*
      let nextOp = null;
      new MutationObserver(() => {
          if (nextOp) clearTimeout(nextOp);
          nextOp = setTimeout(removeMarkElements, 500);
      }).observe(document.body, { subtree: true, childList: true });
      */

      async function consumeReadRequest() {
          const keywords = await GM.getValue("ophirofox_keywords");
          const published_time = await GM.getValue("ophirofox_published_time");
          const readRequest = { keywords, published_time };
          await GM.deleteValue("ophirofox_keywords");
          await GM.deleteValue("ophirofox_published_time");
          return readRequest;
      }

      async function hasConsumable() {
            try {
                // Récupérer les valeurs stockées avec GM.getValue (équivalent de chrome.storage.local)
                const requestType = await GM.getValue("ophirofox_request_type");
                const keywords = await GM.getValue("ophirofox_keywords");

                // Vérifier si l'\''une des deux clés existe et contient une valeur
                const hasRequestType = requestType !== undefined;
                const hasKeywords = keywords !== undefined;

                // Retourner true si au moins une des clés existe avec une valeur
                return hasRequestType || hasKeywords;
            } catch (error) {
                console.error("Erreur lors de la vérification des consommables:", error);
                return false;
            }
      }

      async function onLoad() {
          ophirofoxRealoadOnExpired();
          const path = window.location.pathname;
          if (!(
              path.startsWith("/Search/Reading") ||
              path.startsWith("/Search/Advanced") ||
              path.startsWith("/Search/AdvancedMobile") ||
              path.startsWith("/Search/Express") ||
              path.startsWith("/Search/Simple") ||
              path.startsWith("/Search/Result") ||
              path.startsWith("/Search/ResultMobile") || 
              path === "/Pdf"
          )) return;

          /* Fix une issue avec le proxy BNF qui redirige vers /Pdf */
          if (path === '\''/Pdf'\'' && await hasConsumable()) {
              window.location.pathname = '\''/Search/Reading'\'';
              return;
          }

          const readRequest = await consumeReadRequest();
          const search_terms = readRequest.keywords;
          const published_time = readRequest.published_time;

          if (!search_terms) return;
          const stopwords = new Set(['\''d'\'', '\''l'\'', '\''et'\'', '\''sans'\'', '\''or'\'']);
          const keywords = search_terms
              .replace(/œ/g, '\''oe'\'')
              .split(/[^\p{L}]+/u)
              .filter(w => !stopwords.has(w))
              .join('\'' '\'');

          const keyword_field_id = path.startsWith("/Search/Result") ? "NativeQuery" : "Keywords";

          onElemAvailable('\''#'\'' + keyword_field_id).then((selector) => {
            const keyword_field = selector;
            keyword_field.value = '\''TIT_HEAD='\'' + keywords;
            keyword_field.form.submit();
          });

          onElemAvailable('\''#DateFilter_DateRange'\'').then((selector) => {
              const date_filter = selector;
              if (date_filter) {
                  if (!published_time) { // Full expand the time range
                      date_filter.value = 9;
                  } else {
                      const publishedDate = new Date(published_time);
                      publishedDate.setUTCHours(0, 0, 0, 0); // Europresse saves the exact UTC date, but "depuis X jours" is based on midnight 
                      const currentDate = new Date();
          
                      const timeDifference = currentDate.getTime() - publishedDate.getTime();
                      // Rounds up for tolerance to be sure to not filtering badly
                      const daysDifference = Math.ceil(timeDifference / (1000 * 60 * 60 * 24));
          
                      let filterValue = 9;
          
                      switch (true) {
                          case (daysDifference <= 1):
                              filterValue = 2; // Depuis hier
                              break;
                          case (daysDifference <= 3):
                              filterValue = 11; // Depuis 3 jours
                              break;
                          case (daysDifference <= 7):
                              filterValue = 3; // Depuis 7 jours
                              break;
                          case (daysDifference <= 30):
                              filterValue = 4; // Depuis 30 jours
                              break;
                          case (daysDifference <= 90):
                              filterValue = 5; // Depuis 3 mois
                              break;
                          case (daysDifference <= 180):
                              filterValue = 6; // Depuis 6 mois
                              break;
                          case (daysDifference <= 365):
                              filterValue = 7; // Depuis 1 an
                              break;
                          case (daysDifference <= 730):
                              filterValue = 8; // Depuis 2 ans
                              break;
                          default:
                              filterValue = 9; // Dans toutes les archives
                              break;
                      }
          
                      date_filter.value = filterValue;
                  }
              }
          });
      }

      function ophirofoxRealoadOnExpired() {
          const params = new URLSearchParams(window.location.search)
          if (params.get("ErrorCode") == "4000112") {
              // session expirée
              window.history.back();
          }
      }

      onLoad().catch(console.error);

      pasteStyle(`
'"$css_europress_str"'
        `);
  }'


# Loop to add each .js and .css files to the userscript
while IFS= read -r line; do
  # Parse JSON using jq
  matches=$(echo "$line" | jq -r '.matches[]')
  js_files=$(echo "$line" | jq -r '.js[]')
  # Check if "css" field exists before iterating
  if jq -e '.css' <<< "$line" > /dev/null; then
    css_files=$(echo "$line" | jq -r '.css[]')
  else
    css_files=""
  fi

  # Iterate through each matches file entry
  while IFS= read -r matches; do
    # Ignore entries containing "config.js"
    if [[ $matches != *"config.js" ]]; then

      # Iterate through each JS file entry
      while IFS= read -r js_file; do
        # Ignore entries containing "config.js"
        if [[ $js_file != *"config.js" ]]; then
          js_str=$(cat ./ophirofox/"$js_file")
        fi
      done <<< "$js_files"

      # Print CSS Files if not empty
      if [ -n "$css_files" ]; then
          css_str=$(command cat ./ophirofox/"$css_files" | indent 4)
      fi

      SCRIPT+=$'
  if (match(hostname, "'"$matches"'")) {

      window.addEventListener("load", function(event) {
      '"$js_str"'
      });

      pasteStyle(`
'"$css_str"'
        `);
  }
'
    fi
  done <<< "$matches"

done <<< "$json_data"

SCRIPT+="})();";
echo "$SCRIPT"

echo "$SCRIPT" > $USERSCRIPT
