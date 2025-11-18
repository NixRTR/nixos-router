# Debugging Commands for /docs/ Blank Page

## 1. Check if docs files exist and their permissions

```bash
# Check if docs directory exists and has files
ls -la /var/lib/router-webui/docs/

# Check if index.html exists
ls -la /var/lib/router-webui/docs/index.html

# Check if assets directory exists
ls -la /var/lib/router-webui/docs/assets/

# Check file permissions (nginx user should be able to read)
stat /var/lib/router-webui/docs/index.html
```

## 2. Check nginx configuration

```bash
# Test nginx configuration
sudo nginx -t

# View the actual nginx config being used
sudo cat /etc/nginx/nginx.conf | grep -A 50 "router-webui"

# Or check the generated config
sudo cat $(systemctl cat nginx | grep -oP 'ExecStart=.*nginx' | awk '{print $2}') 2>/dev/null || \
sudo cat /nix/store/*/nginx.conf | grep -A 50 "router-webui"
```

## 3. Check nginx logs

```bash
# Check nginx error logs
sudo journalctl -u nginx -n 100 --no-pager | grep -i error

# Check nginx access logs for /docs requests
sudo journalctl -u nginx -n 100 --no-pager | grep "/docs"

# Or check actual log files if they exist
sudo tail -50 /var/log/nginx/error.log 2>/dev/null || echo "Log file not found"
sudo tail -50 /var/log/nginx/access.log 2>/dev/null || echo "Log file not found"
```

## 4. Test what nginx is actually serving

```bash
# Test if nginx can serve the file directly
curl -v http://127.0.0.1:8080/docs/

# Check the response headers
curl -I http://127.0.0.1:8080/docs/

# Test if assets are accessible
curl -I http://127.0.0.1:8080/docs/assets/js/index-*.js 2>/dev/null | head -5 || \
echo "Asset files not found - check the actual filename"

# Check what files are in assets/js
ls -la /var/lib/router-webui/docs/assets/js/ 2>/dev/null || echo "Assets directory not found"
```

## 5. Check the actual HTML content

```bash
# View the index.html file
cat /var/lib/router-webui/docs/index.html

# Check what asset paths are referenced in the HTML
grep -o 'src="[^"]*"' /var/lib/router-webui/docs/index.html
grep -o 'href="[^"]*"' /var/lib/router-webui/docs/index.html
```

## 6. Check nginx user permissions

```bash
# Check if nginx user exists and is in router-webui group
id nginx

# Test if nginx user can read the files
sudo -u nginx cat /var/lib/router-webui/docs/index.html 2>&1 | head -5
```

## 7. Check if docs service ran successfully

```bash
# Check if docs install service completed
sudo systemctl status router-webui-docs-init

# View the service logs
sudo journalctl -u router-webui-docs-init -n 50 --no-pager
```

## 8. Test nginx location matching

```bash
# Check which location block matches /docs
# This requires looking at the nginx config, but you can test:
curl -v http://127.0.0.1:8080/docs/ 2>&1 | grep -i "location\|HTTP"

# Test if /docs/assets works
curl -I http://127.0.0.1:8080/docs/assets/ 2>&1 | head -10
```

## 9. Compare with working frontend

```bash
# Check if frontend works (for comparison)
curl -I http://127.0.0.1:8080/

# Check frontend files
ls -la /var/lib/router-webui/frontend/
```

## 10. Check browser console errors

In the browser, open Developer Tools (F12) and check:
- Console tab for JavaScript errors
- Network tab to see which requests are failing (404, etc.)
- Look for requests to `/assets/` that should be `/docs/assets/`

## Quick Diagnostic Script

Run this to get a comprehensive overview:

```bash
echo "=== Docs Directory ==="
ls -la /var/lib/router-webui/docs/ 2>&1 | head -20

echo -e "\n=== Index.html exists? ==="
[ -f /var/lib/router-webui/docs/index.html ] && echo "YES" || echo "NO"

echo -e "\n=== Index.html content (first 20 lines) ==="
head -20 /var/lib/router-webui/docs/index.html 2>&1

echo -e "\n=== Asset paths in HTML ==="
grep -E '(src|href)=' /var/lib/router-webui/docs/index.html | head -10

echo -e "\n=== Assets directory ==="
ls -la /var/lib/router-webui/docs/assets/ 2>&1 | head -10

echo -e "\n=== Nginx can read file? ==="
sudo -u nginx test -r /var/lib/router-webui/docs/index.html && echo "YES" || echo "NO"

echo -e "\n=== Test HTTP response ==="
curl -I http://127.0.0.1:8080/docs/ 2>&1 | head -10

echo -e "\n=== Nginx error logs (last 10) ==="
sudo journalctl -u nginx -n 10 --no-pager | grep -i error
```

