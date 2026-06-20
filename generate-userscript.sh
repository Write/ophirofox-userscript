#!/bin/bash

# If first argument is a directory, use it as the ophirofox source dir
# and $2 as version. Otherwise fall back to ./ophirofox and $1 as version.
if [ -d "$1" ]; then
    OPHIROFOX_DIR="$1"
    VERSION="${2:-}"
else
    OPHIROFOX_DIR="./ophirofox"
    VERSION="$1"
fi

USERSCRIPT="./ophirofox.user.js"
MANIFEST="$OPHIROFOX_DIR/manifest.json"

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

read -r -d '' SETTINGS_PANEL_BLOCK << 'JSBLOCK'
  function showSettingsPanel() {
      return new Promise(async (resolve) => {
          const currentUniversity = await GM.getValue("universityName", null);
          const openLinksNewTab = await GM.getValue("open_links_new_tab", false);
          const autoOpenLink = await GM.getValue("auto_open_link", false);

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
              max-width: 520px; width: 90%; max-height: 85vh;
              box-shadow: 0 8px 32px rgba(0,0,0,0.3);
              display: flex; flex-direction: column;
          `;
          const title = document.createElement('h2');
          title.textContent = 'Parametres Ophirofox';
          title.style.cssText = 'margin: 0 0 4px; font-size: 18px; color: #222;';

          const searchInput = document.createElement('input');
          searchInput.type = 'search';
          searchInput.placeholder = 'Rechercher un partenaire...';
          searchInput.style.cssText = `
              width: 100%; padding: 8px; font-size: 14px;
              border: 1px solid #ccc; border-radius: 6px;
              margin: 12px 0 8px; box-sizing: border-box;
          `;

          const listContainer = document.createElement('div');
          listContainer.style.cssText = `
              max-height: 250px; overflow-y: auto;
              border: 1px solid #e6e6e6; border-radius: 6px;
              margin-bottom: 12px;
          `;

          let selectedName = currentUniversity || ophirofox_config_list[0].name;

          function renderList(filter) {
              listContainer.innerHTML = '';
              const f = (filter || '').toLowerCase();
              ophirofox_config_list.forEach(uni => {
                  if (f && !uni.name.toLowerCase().includes(f)) return;
                  const label = document.createElement('label');
                  label.style.cssText = `
                      display: flex; align-items: center; gap: 8px;
                      padding: 6px 10px; cursor: pointer;
                      font-size: 14px; border-bottom: 1px solid #f0f0f0;
                  `;
                  const radio = document.createElement('input');
                  radio.type = 'radio';
                  radio.name = 'partner';
                  radio.value = uni.name;
                  radio.checked = uni.name === selectedName;
                  radio.addEventListener('change', () => { selectedName = uni.name; });
                  label.appendChild(radio);
                  label.appendChild(document.createTextNode(uni.name));
                  listContainer.appendChild(label);
              });
          }
          renderList();
          searchInput.addEventListener('input', () => renderList(searchInput.value));

          const togglesContainer = document.createElement('div');
          togglesContainer.style.cssText = 'margin-bottom: 12px;';

          const newTabLabel = document.createElement('label');
          newTabLabel.style.cssText = 'display: flex; align-items: center; gap: 8px; padding: 6px 0; font-size: 14px; cursor: pointer;';
          const newTabCheck = document.createElement('input');
          newTabCheck.type = 'checkbox';
          newTabCheck.checked = openLinksNewTab;
          newTabLabel.appendChild(newTabCheck);
          newTabLabel.appendChild(document.createTextNode('Ouvrir les liens Europresse dans un nouvel onglet'));

          const autoOpenLabel = document.createElement('label');
          autoOpenLabel.style.cssText = 'display: flex; align-items: center; gap: 8px; padding: 6px 0; font-size: 14px; cursor: pointer;';
          const autoOpenCheck = document.createElement('input');
          autoOpenCheck.type = 'checkbox';
          autoOpenCheck.checked = autoOpenLink;
          autoOpenLabel.appendChild(autoOpenCheck);
          autoOpenLabel.appendChild(document.createTextNode("Ouvrir automatiquement le lien lorsqu'un seul resultat est trouve"));

          togglesContainer.appendChild(newTabLabel);
          togglesContainer.appendChild(autoOpenLabel);

          const btn = document.createElement('button');
          btn.textContent = 'Enregistrer';
          btn.style.cssText = `
              width: 100%; padding: 10px; font-size: 15px; font-weight: bold;
              background: #1a73e8; color: #fff; border: none;
              border-radius: 6px; cursor: pointer;
          `;
          btn.addEventListener('click', async () => {
              await GM.setValue("universityName", selectedName);
              await GM.setValue("open_links_new_tab", newTabCheck.checked);
              await GM.setValue("auto_open_link", autoOpenCheck.checked);
              overlay.remove();
              resolve({ universityName: selectedName, openLinksNewTab: newTabCheck.checked, autoOpenLink: autoOpenCheck.checked });
          });

          box.append(title, searchInput, listContainer, togglesContainer, btn);
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

  function isApplePlatform() {
      return /iPhone|iPad|Macintosh/.test(navigator.userAgent);
  }

  const DEFAULT_SETTINGS = {
      partner_name: "Pas d'intermediaire",
      partner_AUTH_URL: "https://nouveau.europresse.com/Login",
      open_links_new_tab: false,
      auto_open_link: false,
  };

  let current_settings = DEFAULT_SETTINGS;

  async function getSettings() {
      try {
          current_settings.open_links_new_tab = await GM.getValue("open_links_new_tab", false);
          current_settings.auto_open_link = await GM.getValue("auto_open_link", false);
      } catch(e) {}
      return current_settings;
  }

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
      await GM.setValue("ophirofox_request_type", { type: 'read' });
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
          await getSettings();
          await setKeywords(keywords, publishedTime);
          const obj = await ophirofox_config;
          if (current_settings.open_links_new_tab) {
              window.open(obj.AUTH_URL, "_blank");
          } else {
              window.location = obj.AUTH_URL;
          }
      }
      ophirofox_config.then(({ AUTH_URL }) => {
          a.href = AUTH_URL;
      });

      if (isApplePlatform()) {
          const wrapper = document.createElement("span");
          wrapper.style.cssText = "display: inline-flex; align-items: center; gap: 6px;";
          wrapper.appendChild(a);
          const cog = document.createElement("button");
          cog.textContent = "\u2699";
          cog.title = "Parametres Ophirofox";
          cog.style.cssText = "background: white; border: 1px solid #ccc; border-radius: 4px; cursor: pointer; font-size: 16px; padding: 2px 6px; line-height: 1; z-index: 20;";
          cog.addEventListener('click', async (evt) => {
              evt.preventDefault();
              evt.stopPropagation();
              const result = await showSettingsPanel();
              universityName = result.universityName;
              settingsOpenLinksNewTab = result.openLinksNewTab;
              settingsAutoOpenLink = result.autoOpenLink;
              await getSettings();
          });
          wrapper.appendChild(cog);
          return wrapper;
      }
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

      async function consumeRequestType() {
          const requestType = await GM.getValue("ophirofox_request_type");
          await GM.deleteValue("ophirofox_request_type");
          return requestType;
      }

      async function consumeReadRequest() {
          const keywords = await GM.getValue("ophirofox_keywords");
          const published_time = await GM.getValue("ophirofox_published_time");
          const readRequest = { keywords, published_time };
          await GM.deleteValue("ophirofox_keywords");
          await GM.deleteValue("ophirofox_published_time");
          await GM.deleteValue("ophirofox_request_type");
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

      function readWhenOnlyOneResult() {
          const observer = new MutationObserver(async () => {
              const linkElement = document.querySelector('a.docList-links');
              if (linkElement) {
                  linkElement.click();
                  observer.disconnect();
              }
          });
          observer.observe(document.body, { childList: true, subtree: true });
      }

      async function onLoad() {
          await getSettings();
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

          if (!await hasConsumable()) {
              if (path.startsWith("/Search/Result")) {
                  onElemAvailable('.resultOperations-count').then((countElem) => {
                      if (countElem && countElem.textContent === '1') {
                          if (current_settings.auto_open_link) {
                              readWhenOnlyOneResult();
                          }
                      } else if (countElem && countElem.textContent === '0') {
                          const queryField = document.querySelector('#Keywords');
                          if (queryField && queryField.value.startsWith('TIT_HEAD=')) {
                              queryField.value = queryField.value.replace('TIT_HEAD=', 'TEXT=');
                              const btnSearch = document.querySelector('#btnSearch');
                              if (btnSearch) btnSearch.click();
                          }
                      }
                  });
              }
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
              const partner = getOphirofoxConfigByName(universityName);
              if (partner && partner.AUTH_URL) {
                  window.location = partner.AUTH_URL;
              } else {
                  window.location = ophirofox_config_list[0].AUTH_URL;
              }
          }
      }

      onLoad().catch(console.error);
JSBLOCK

# ---- Construction du header ----

SCRIPT=$(cat <<-END
// ==UserScript==
// @version $VERSION
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
 * ║  choisir votre universite et vos preferences.        ║
 * ║                                                      ║
 * ║  Pour changer ensuite, trois options :               ║
 * ║                                                      ║
 * ║  1. Menu de l'"'"'extension (icone dans la barre)   ║
 * ║     → clic sur le script                             ║
 * ║     → "Parametres Ophirofox"                         ║
 * ║                                                      ║
 * ║  2. Icône engrenage (⚙) a cote du bouton            ║
 * ║     "Lire sur Europresse" (sur iOS/macOS)            ║
 * ║                                                      ║
 * ║  3. Console JS (F12), sur un site ou le script       ║
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
      node.appendChild(document.createTextNode(str.replace(/(?:\s*!important)?;/g, '"'"' !important;'"'"')));
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
SCRIPT+="$SETTINGS_PANEL_BLOCK"
SCRIPT+='
  let universityName = await GM.getValue("universityName", null);
  let settingsOpenLinksNewTab = await GM.getValue("open_links_new_tab", false);
  let settingsAutoOpenLink = await GM.getValue("auto_open_link", false);
  if (universityName === null) {
      const result = await showSettingsPanel();
      universityName = result.universityName;
      settingsOpenLinksNewTab = result.openLinksNewTab;
      settingsAutoOpenLink = result.autoOpenLink;
  }
  if (typeof GM !== "undefined" && typeof GM.registerMenuCommand === "function") {
      GM.registerMenuCommand("Parametres Ophirofox", async () => {
          const result = await showSettingsPanel();
          universityName = result.universityName;
          settingsOpenLinksNewTab = result.openLinksNewTab;
          settingsAutoOpenLink = result.autoOpenLink;
          location.reload();
      });
  } else if (typeof GM_registerMenuCommand === "function") {
      GM_registerMenuCommand("Parametres Ophirofox", async () => {
          const result = await showSettingsPanel();
          universityName = result.universityName;
          settingsOpenLinksNewTab = result.openLinksNewTab;
          settingsAutoOpenLink = result.autoOpenLink;
          location.reload();
      });
  }
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

css_europress_str=$(command cat "$OPHIROFOX_DIR/content_scripts/europresse_article.css" | indent 4)
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
        if [[ $js_file == *"mediapart.js" ]]; then
          js_str=$(python3 adapt-special-case.py mediapart < "$OPHIROFOX_DIR/$js_file")
        elif [[ $js_file == *"arret-sur-images.js" ]]; then
          js_str=$(python3 adapt-special-case.py arretsurimages < "$OPHIROFOX_DIR/$js_file")
        elif [[ $js_file == *"alternatives-economiques.js" ]]; then
          js_str=$(python3 adapt-special-case.py alternativeseconomiques < "$OPHIROFOX_DIR/$js_file")
        elif [[ $js_file == *"pressreader.js" ]]; then
          js_str=$(python3 adapt-special-case.py pressreader < "$OPHIROFOX_DIR/$js_file")
        elif [[ $js_file != *"config.js" ]]; then
          js_str=$(cat "$OPHIROFOX_DIR/$js_file")
        fi
      done <<< "$js_files"

      if [ -n "$css_files" ]; then
          css_str=$(command cat "$OPHIROFOX_DIR/$css_files" | indent 4)
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
echo "$SCRIPT" > "$USERSCRIPT"
