import sys
import argparse
from mitmproxy import http
import re
import yaml

def load_config(config_path):
    try:
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"error: config file '{config_path}' not found.")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"error parsing config file: {e}")
        sys.exit(1)

# parse command-line arguments
parser = argparse.ArgumentParser(description="proxy script with custom configuration")
parser.add_argument("-c", "--config", required=True, help="path to the yaml config file")
parser.add_argument("-p", "--port", type=int, default=8080, help="port to run the proxy on")
args = parser.parse_args()

# load configuration
config = load_config(args.config)

ORIGINAL_HOST = config['ORIGINAL_HOST']
NEW_HOST = config['NEW_HOST']
ADDITIONAL_DOMAINS = config['ADDITIONAL_DOMAINS']
TRACKING_SCRIPTS = config['TRACKING_SCRIPTS']
INJECT_SCRIPT = config['INJECT_SCRIPT']
STRING_REPLACEMENTS = config['STRING_REPLACEMENTS']

def get_host_and_port(flow: http.HTTPFlow) -> tuple:
    if 'X-Forwarded-Host' in flow.request.headers:
        forwarded_host = flow.request.headers['X-Forwarded-Host']
        if ':' in forwarded_host:
            return forwarded_host.split(':')
        else:
            return forwarded_host, '443' if flow.request.scheme == 'https' else '80'
    else:
        if ':' in NEW_HOST:
            return NEW_HOST.split(':')
        else:
            return NEW_HOST, str(args.port)

def request(flow: http.HTTPFlow) -> None:
    original_host = flow.request.host
    new_host, new_port = get_host_and_port(flow)

    if flow.request.host == new_host or flow.request.host == f"{new_host}:{new_port}":
        flow.request.host = ORIGINAL_HOST
        flow.request.headers["Host"] = ORIGINAL_HOST
        flow.request.path = re.sub(r':\d+', '', flow.request.path)
    elif any(domain in flow.request.host for domain in ADDITIONAL_DOMAINS):
        flow.request.headers["Host"] = original_host
    else:
        flow.request.host = ORIGINAL_HOST
        flow.request.headers["Host"] = ORIGINAL_HOST

    if 'X-Forwarded-Proto' in flow.request.headers:
        flow.request.scheme = flow.request.headers['X-Forwarded-Proto']
    else:
        flow.request.scheme = "https"

    flow.request.port = 443 if flow.request.scheme == "https" else 80

def response(flow: http.HTTPFlow) -> None:
    if flow.response and flow.response.content:
        content = flow.response.text
        new_host, new_port = get_host_and_port(flow)

        # replace the main domain
        content = re.sub(
            r'(https?:)?//' + re.escape(ORIGINAL_HOST),
            f'//{new_host}:{new_port}',
            content
        )

        # replace additional domains
        for domain in ADDITIONAL_DOMAINS:
            content = content.replace(f'"//{domain}', f'"https://{domain}')
            content = content.replace(f"'//{domain}", f"'https://{domain}")

        # remove tracking scripts
        for script in TRACKING_SCRIPTS:
            content = re.sub(r'<script[^>]*src=["\']' + script + r'["\'][^>]*>.*?</script>', '', content, flags=re.DOTALL)

        # perform string replacements
        for replacement in STRING_REPLACEMENTS:
            content = content.replace(replacement['from'], replacement['to'])

        # inject custom script before </body>
        content = content.replace('</body>', f'{INJECT_SCRIPT}</body>')

        flow.response.text = content

    # replace hosts in headers
    for header in flow.response.headers:
        if ORIGINAL_HOST in flow.response.headers[header]:
            flow.response.headers[header] = flow.response.headers[header].replace(
                ORIGINAL_HOST, f'{new_host}:{new_port}'
            )

    # handle redirects
    if flow.response.status_code in [301, 302, 307, 308]:
        if "Location" in flow.response.headers:
            location = flow.response.headers["Location"]
            if ORIGINAL_HOST in location:
                flow.response.headers["Location"] = location.replace(
                    ORIGINAL_HOST, f'{new_host}:{new_port}'
                )

    # remove security headers that might cause issues
    headers_to_remove = [
        "Strict-Transport-Security",
        "Content-Security-Policy",
        "X-Frame-Options",
    ]
    for header in headers_to_remove:
        if header in flow.response.headers:
            del flow.response.headers[header]

def start():
    from mitmproxy.tools.main import mitmdump
    mitmdump(['-s', __file__, '-p', str(args.port)])

if __name__ == '__main__':
    start()
