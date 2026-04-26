#!/usr/bin/env python3
"""
Broken Link Checker for Toprank.
Crawls a website starting from a given URL and identifies broken links (HTTP 4xx/5xx).

Usage:
  python3 checker.py --url https://example.com --max-pages 20
"""

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from collections import deque
from html.parser import HTMLParser

class LinkParser(HTMLParser):
    def __init__(self, base_url):
        super().__init__()
        self.base_url = base_url
        self.links = set()

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            for attr, value in attrs:
                if attr == 'href':
                    url = urllib.parse.urljoin(self.base_url, value)
                    # Remove fragment
                    url = urllib.parse.urljoin(url, urllib.parse.urlparse(url).path)
                    if url.startswith('http'):
                        self.links.add(url)

def check_url(url, timeout=10):
    """Checks a URL and returns (status_code, error_msg)."""
    req = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'ToprankBrokenLinkChecker/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.getcode(), None
    except urllib.error.HTTPError as e:
        return e.code, str(e.reason)
    except urllib.error.URLError as e:
        return None, str(e.reason)
    except Exception as e:
        return None, str(e)

def crawl(start_url, max_pages=50):
    domain = urllib.parse.urlparse(start_url).netloc
    visited = set()
    queue = deque([start_url])
    broken_links = []
    pages_crawled = 0

    print(f"Starting crawl of {start_url} (limit: {max_pages} pages)...", file=sys.stderr)

    while queue and pages_crawled < max_pages:
        current_url = queue.popleft()
        if current_url in visited:
            continue
        
        visited.add(current_url)
        pages_crawled += 1
        
        print(f"[{pages_crawled}/{max_pages}] Checking: {current_url}", file=sys.stderr)
        
        # We need to GET the page to find more links
        try:
            req = urllib.request.Request(current_url, headers={'User-Agent': 'ToprankBrokenLinkChecker/1.0'})
            with urllib.request.urlopen(req, timeout=10) as response:
                if response.getcode() >= 400:
                    broken_links.append({"url": current_url, "status": response.getcode(), "reason": "Page itself is broken"})
                    continue
                
                content_type = response.headers.get('Content-Type', '')
                if 'text/html' not in content_type:
                    continue
                
                html = response.read().decode('utf-8', errors='ignore')
                parser = LinkParser(current_url)
                parser.feed(html)
                
                # Check links found on this page
                found_links = list(parser.links)
                with ThreadPoolExecutor(max_workers=5) as executor:
                    future_to_url = {executor.submit(check_url, link): link for link in found_links}
                    for future in as_completed(future_to_url):
                        link = future_to_url[future]
                        status, reason = future.result()
                        if status is None or status >= 400:
                            broken_links.append({
                                "source": current_url,
                                "target": link,
                                "status": status,
                                "reason": reason
                            })
                        
                        # Add internal links to queue
                        if urllib.parse.urlparse(link).netloc == domain and link not in visited:
                            queue.append(link)

        except Exception as e:
            print(f"Error crawling {current_url}: {e}", file=sys.stderr)
            broken_links.append({"url": current_url, "status": None, "reason": str(e)})

    return broken_links

def main():
    parser = argparse.ArgumentParser(description="Broken Link Checker")
    parser.add_argument("--url", required=True, help="Starting URL")
    parser.add_argument("--max-pages", type=int, default=20, help="Maximum pages to crawl")
    parser.add_argument("--output", help="Output JSON file")
    
    args = parser.parse_args()
    
    broken = crawl(args.url, args.max_pages)
    
    result = {
        "start_url": args.url,
        "max_pages": args.max_pages,
        "broken_links_count": len(broken),
        "broken_links": broken
    }
    
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(result, f, indent=2)
    else:
        print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
