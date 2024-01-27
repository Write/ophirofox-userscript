#!/bin/bash

USERSCRIPT="./ophirofox.user.js"
MANIFEST="./ophirofox/manifest.json"

json_data=$(jq -rc '.content_scripts[] ' "$MANIFEST")
partners=$(jq -rc '.browser_specific_settings.ophirofox_metadata.partners' "$MANIFEST")
europress_urls=$(jq -rc 'del(.optional_permissions[] | select(. == "webNavigation"))' "$MANIFEST" | jq -rc '.optional_permissions[]')
europress_urls_count=$(jq -rc 'del(.optional_permissions[] | select(. == "webNavigation"))' "$MANIFEST" | jq -rc '.optional_permissions[]' | wc -l)


SCRIPT=$(cat <<-END
// ==UserScript==
// @version     $1
// @author      Write
// @name        OphirofoxScript
// @grant    GM.getValue
// @grant    GM.setValue
// @grant    GM.deleteValue
END
)
SCRIPT+=$'\n'


# Loop to add @include entries
while IFS= read -r europress_single_url; do
  SCRIPT+="// @include $europress_single_url"$'\n'
done <<< "$europress_urls"

while IFS= read -r line; do
  # Parse JSON using jq
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
   *   CONFIG
   * ----------------
   * */

  // Changer de votre université ici, voir la liste ci-dessous dans ophirofox_config_list
  // 
  const universityName = "Bibliotheque nationale et universitaire de Strasbourg"

  /* ----------------
   *   HELPERS
   * ----------------
   * */

  const current = window.location.href;
  const hostname = window.location.hostname;

  function match(str, rule) {
      var escapeRegex = (str) => str.replace(/([.*+?^=!:${}()|\[\]\/\\])/g, "\\$1");
      return new RegExp("^" + rule.split("*").map(escapeRegex).join(".*") + "$").test(str);
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

  async function setKeywords(keywords) {
    await GM.setValue("ophirofox_keywords", keywords);
  }

  async function ophirofoxEuropresseLink(keywords) {
    keywords = keywords ? keywords.trim() : document.querySelector("h1").textContent;
    const a = document.createElement("a");
    a.textContent = "Lire sur Europresse";
    a.className = "ophirofox-europresse";
    a.onmousedown = setKeywords(keywords);
    a.onclick = async function (evt) {
      evt.preventDefault();
      await Promise.resolve([ophirofox_config, setKeywords(keywords)])
      const obj = await ophirofox_config;
      window.location = obj.AUTH_URL;
    }
    ophirofox_config.then(({ AUTH_URL }) => { a.href = AUTH_URL });
    return a;
  }

'

SCRIPT+=$'if ('
counter=1
while IFS= read -r europress_single_url; do

  if [[ "$counter" -eq "$europress_urls_count" ]]; then
      # last element, close the parenthesis.
        SCRIPT+=$'
  "'"$europress_single_url"'".includes(hostname)) {'
  else
        SCRIPT+=$'
  "'"$europress_single_url"'".includes(hostname) ||'
  fi
  ((counter++))
done <<< "$europress_urls"

# Inject europress_article.{css,js..}
#  js_europress_article_str=$(cat ./ophirofox/content_scripts/europresse_article.js)
# js_europress_search_str=$(cat ./ophirofox/content_scripts/europresse_search.js)
  css_europress_str=$(cat ./ophirofox/content_scripts/europresse_article.css)
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

      async function consumeSearchTerms() {
        const keywords = await GM.getValue("ophirofox_keywords");
        await GM.deleteValue("ophirofox_keywords");
        return keywords;
      }

      async function onLoad() {
          ophirofoxRealoadOnExpired();
          const path = window.location.pathname;
          if (!(
              path.startsWith("/Search/Reading") ||
              path.startsWith("/Search/Advanced") ||
              path.startsWith("/Search/AdvancedMobile") ||
              path.startsWith("/Search/Express") ||
              path.startsWith("/Search/Simple")
          )) return;
          const search_terms = await consumeSearchTerms();
          if (!search_terms) return;
          const stopwords = new Set(['\''d'\'', '\''l'\'', '\''et'\'', '\''sans'\'']);
          const keywords = search_terms
              .replace(/œ/g, '\''oe'\'')
              .split(/[^\p{L}]+/u)
              .filter(w => !stopwords.has(w))
              .join('\'' '\'');


          onElemAvailable('\''#Keywords'\'').then((selector) => {
            const keyword_field = selector;
            keyword_field.value = '\''TIT_HEAD='\'' + keywords;
            keyword_field.form.submit();
          });

          onElemAvailable('\''#DateFilter_DateRange'\'').then((selector) => {
            const date_filter = selector;
            if (date_filter) date_filter.value = 9;
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

      pasteStyle(`'"$css_europress_str"'`);
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
          css_str=$(cat ./ophirofox/"$css_files")
      fi

      SCRIPT+=$'
  if ("'"$matches"'".includes(hostname)) {

      window.addEventListener("load", function(event) {
      '"$js_str"'
      });

      pasteStyle(`'"$css_str"'`);
  }
'
    fi
  done <<< "$matches"

done <<< "$json_data"

SCRIPT+="})();";
echo "$SCRIPT"

echo "$SCRIPT" > $USERSCRIPT
