#!/bin/bash
# Test CAKE API endpoints
# Usage: ./test-cake-api.sh <TOKEN>

TOKEN=$1
BASE_URL="http://192.168.3.1:8080"

if [ -z "$TOKEN" ]; then
    echo "Usage: $0 <JWT_TOKEN>"
    echo "Get token from browser localStorage: localStorage.getItem('access_token')"
    exit 1
fi

echo "========================================="
echo "Testing CAKE API Endpoints"
echo "========================================="
echo ""

echo "1. Testing /api/cake/status"
echo "---------------------------"
curl -s -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     "${BASE_URL}/api/cake/status" | jq '.'
echo ""
echo ""

echo "2. Testing /api/cake/current"
echo "----------------------------"
curl -s -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     "${BASE_URL}/api/cake/current" | jq '.'
echo ""
echo ""

echo "3. Testing /api/cake/history?range=1h"
echo "-------------------------------------"
curl -s -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     "${BASE_URL}/api/cake/history?range=1h" | jq '.'
echo ""
echo ""

echo "4. Testing /api/cake/history?range=1h&interface=ppp0"
echo "---------------------------------------------------"
curl -s -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     "${BASE_URL}/api/cake/history?range=1h&interface=ppp0" | jq '.'

