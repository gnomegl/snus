#!/usr/bin/env bash

# SnusBase Query Tool
# A tool to search SnusBase data and combolists, displaying results in a terminal-friendly format
# Compatible with macOS and Linux

SNUSBASE_API_KEY="sbtx7de5atdtbs2tlamm5ohvz5vlom"
SEARCH_API_URL="https://api.snusbase.com/data/search"
COMBO_API_URL="https://api.snusbase.com/temp/combolists"
SEARCH_TYPE="username"
SEARCH_TERM=""
USE_WILDCARD=true
OUTPUT_FORMAT="pretty"
COMBO_LIST=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;91m'
NC='\033[0m'
BOLD='\033[1m'

# Check for required dependencies
check_dependencies() {
  local missing_deps=()

  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi

  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
    echo
    if [[ "$OSTYPE" == "darwin"* ]]; then
      echo "Install on macOS with:"
      echo "  brew install ${missing_deps[*]}"
    else
      echo "Install on Linux with:"
      echo "  apt install ${missing_deps[*]}  # Debian/Ubuntu"
      echo "  yum install ${missing_deps[*]}  # RHEL/CentOS"
    fi
    exit 1
  fi
}

show_usage() {
  echo -e "${BOLD}SnusBase Query Tool${NC}"
  echo "Usage: $0 [options] -q SEARCH_TERM"
  echo
  echo "Options:"
  echo "  -t, --type TYPE       Search type: username, email, hash, password, ip (default: username)"
  echo "  -q, --query TERM      Term to search for (required)"
  echo "  -w, --wildcard        Use wildcard search (default: enabled)"
  echo "  -n, --no-wildcard     Disable wildcard search"
  echo "  -j, --json            Output results in JSON format"
  echo "  -k, --key KEY         Specify SnusBase API key"
  echo "  -c, --combo           Include combo lists in search (default: enabled)"
  echo "  -N, --no-combo        Exclude combo lists from search"
  echo "  -h, --help            Show this help message"
  echo
  echo "Example: $0 -t email -q example@domain.com"
}

while [[ $# -gt 0 ]]; do
  case $1 in
  -t | --type)
    SEARCH_TYPE="$2"
    shift 2
    ;;
  -q | --query)
    SEARCH_TERM="$2"
    shift 2
    ;;
  -w | --wildcard)
    USE_WILDCARD=true
    shift
    ;;
  -n | --no-wildcard)
    USE_WILDCARD=false
    shift
    ;;
  -j | --json)
    OUTPUT_FORMAT="json"
    shift
    ;;
  -k | --key)
    SNUSBASE_API_KEY="$2"
    shift 2
    ;;
  -c | --combo)
    COMBO_LIST=true
    shift
    ;;
  -N | --no-combo)
    COMBO_LIST=false
    shift
    ;;
  -h | --help)
    show_usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    show_usage
    exit 1
    ;;
  esac
done

# Check dependencies before proceeding
check_dependencies

if [[ -z "$SEARCH_TERM" ]]; then
  echo -e "${RED}Error: Search term is required${NC}"
  show_usage
  exit 1
fi

valid_types=("username" "email" "hash" "password" "ip")
if [[ ! " ${valid_types[*]} " =~ \ ${SEARCH_TYPE}\  ]]; then
  echo -e "${RED}Error: Invalid search type '${SEARCH_TYPE}'${NC}"
  show_usage
  exit 1
fi

SEARCH_RESPONSE=""
COMBO_RESPONSE=""
TOTAL_RESULTS=0

OPTIONS=()
if [[ "$USE_WILDCARD" = true ]]; then
  OPTIONS+=("wildcard")
fi

JSON_PAYLOAD=$(jq -n \
  --arg type "$SEARCH_TYPE" \
  --arg term "$SEARCH_TERM" \
  --argjson options "$(printf '%s\n' "${OPTIONS[@]}" | jq -R . | jq -s .)" \
  '{types: [$type], terms: [$term], options: $options}')

echo -e "${CYAN}Searching SnusBase databases for ${BOLD}$SEARCH_TYPE:$SEARCH_TERM${NC}..."
SEARCH_RESPONSE=$(curl -s "$SEARCH_API_URL" \
  -H "auth: $SNUSBASE_API_KEY" \
  -H "content-type: application/json" \
  --data-raw "$JSON_PAYLOAD")

if ! echo "$SEARCH_RESPONSE" | jq -e . >/dev/null 2>&1; then
  echo -e "${RED}Error: Invalid response received from search API${NC}"
  echo "$SEARCH_RESPONSE"
  exit 1
fi

SEARCH_SIZE=$(echo "$SEARCH_RESPONSE" | jq -r '.size')
TOTAL_RESULTS=$SEARCH_SIZE

if [[ "$COMBO_LIST" = true ]]; then
  echo -e "${CYAN}Searching SnusBase combo lists for ${BOLD}$SEARCH_TERM${NC}..."
  COMBO_RESPONSE=$(curl -s "$COMBO_API_URL/$SEARCH_TERM" \
    -H "auth: $SNUSBASE_API_KEY" \
    -H "content-type: application/json")

  if ! echo "$COMBO_RESPONSE" | jq -e . >/dev/null 2>&1; then
    echo -e "${RED}Error: Invalid response received from combo lists API${NC}"
    echo "$COMBO_RESPONSE"
    COMBO_RESPONSE=""
  else
    COMBO_SIZE=$(echo "$COMBO_RESPONSE" | jq -r '.result | map(length) | add')
    TOTAL_RESULTS=$((TOTAL_RESULTS + COMBO_SIZE))
  fi
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  if [[ -n "$COMBO_RESPONSE" ]]; then
    jq -n \
      --argjson search "$SEARCH_RESPONSE" \
      --argjson combo "$COMBO_RESPONSE" \
      '{search: $search, combo_lists: $combo, total_results: '"$TOTAL_RESULTS"'}'
  else
    echo "$SEARCH_RESPONSE" | jq .
  fi
  exit 0
fi

TOOK=$(echo "$SEARCH_RESPONSE" | jq -r '.took')

echo -e "${GREEN}Found ${BOLD}$TOTAL_RESULTS${NC}${GREEN} total results (Search: $SEARCH_SIZE)"
if [[ "$COMBO_LIST" = true && -n "$COMBO_RESPONSE" ]]; then
  echo -e "${GREEN}Search took ${BOLD}${TOOK}ms${NC}"
else
  echo -e "${GREEN}Search took ${BOLD}${TOOK}ms${NC}"
fi

if [[ "$TOTAL_RESULTS" -eq 0 ]]; then
  echo -e "${YELLOW}No results found.${NC}"
  exit 0
fi

display_combo_results() {
  if [[ -z "$COMBO_RESPONSE" ]]; then
    return
  fi

  echo -e "\n${ORANGE}${BOLD}===== COMBO LISTS RESULTS =====${NC}\n"

  SOURCES=$(echo "$COMBO_RESPONSE" | jq -r '.result | keys[]')
  COUNTER=1

  for SOURCE in $SOURCES; do
    FORMATTED_SOURCE=$(echo "$SOURCE" | sed -E 's/_/ /g')

    echo -e "\n${PURPLE}=== Source: ${BOLD}$FORMATTED_SOURCE${NC} ${PURPLE}===${NC}"

    ENTRIES=$(echo "$COMBO_RESPONSE" | jq -r --arg source "$SOURCE" '.result[$source] | length')

    for ((i = 0; i < $ENTRIES; i++)); do
      ENTRY=$(echo "$COMBO_RESPONSE" | jq -r --arg source "$SOURCE" --argjson idx "$i" '.result[$source][$idx]')

      echo -e "${BLUE}--- Combo #${COUNTER} ---${NC}"

      USERNAME=$(echo "$ENTRY" | jq -r '.username')
      PASSWORD=$(echo "$ENTRY" | jq -r '.password')

      echo -e "  ${BOLD}${GREEN}username:${NC} $USERNAME"
      echo -e "  ${BOLD}${RED}password:${NC} $PASSWORD"

      COUNTER=$((COUNTER + 1))
    done
  done
}

display_search_results() {
  if [[ "$SEARCH_SIZE" -eq 0 ]]; then
    return
  fi

  echo -e "\n${ORANGE}${BOLD}===== DATABASE SEARCH RESULTS =====${NC}\n"

  SOURCES=$(echo "$SEARCH_RESPONSE" | jq -r '.results | keys[]')
  COUNTER=1

  for SOURCE in $SOURCES; do
    FORMATTED_SOURCE=$(echo "$SOURCE" | sed -E 's/_/ /g' | sed -E 's/([0-9]+)_//g')

    echo -e "\n${PURPLE}=== Source: ${BOLD}$FORMATTED_SOURCE${NC} ${PURPLE}===${NC}"

    ENTRIES=$(echo "$SEARCH_RESPONSE" | jq -r --arg source "$SOURCE" '.results[$source] | length')

    for ((i = 0; i < $ENTRIES; i++)); do
      ENTRY=$(echo "$SEARCH_RESPONSE" | jq -r --arg source "$SOURCE" --argjson idx "$i" '.results[$source][$idx]')

      echo -e "${BLUE}--- Result #${COUNTER} ---${NC}"

      echo "$ENTRY" | jq -r 'to_entries | .[] | select(.key != "_domain") | "\(.key): \(.value)"' | while read line; do
        KEY=$(echo "$line" | cut -d':' -f1)
        VALUE=$(echo "$line" | cut -d':' -f2- | sed 's/^ //')

        case "$KEY" in
        username)
          echo -e "  ${BOLD}${GREEN}$KEY:${NC} $VALUE"
          ;;
        email)
          echo -e "  ${BOLD}${YELLOW}$KEY:${NC} $VALUE"
          ;;
        password)
          echo -e "  ${BOLD}${RED}$KEY:${NC} $VALUE"
          ;;
        lastip)
          echo -e "  ${BOLD}${CYAN}$KEY:${NC} $VALUE"
          ;;
        *)
          echo -e "  ${BOLD}$KEY:${NC} $VALUE"
          ;;
        esac
      done

      COUNTER=$((COUNTER + 1))
    done
  done
}

if [[ "$COMBO_LIST" = true ]]; then
  display_combo_results
fi

display_search_results

echo -e "\n${GREEN}Search complete.${NC}"
