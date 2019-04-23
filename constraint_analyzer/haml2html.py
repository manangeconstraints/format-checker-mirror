from urllib.parse import urlencode
from urllib.request import Request, urlopen
from bs4 import BeautifulSoup
import sys

def haml2html(file):
    if not file.endswith('.haml'):
        return
    f = open(file, 'r')
    c = f.read()

    url = 'https://haml2erb.org/' # Set destination URL here
    post_fields = {'haml': c, 'converter': 'herbalizer'}     # Set POST fields here
    
    request = Request(url, urlencode(post_fields).encode())
    json = urlopen(request).read().decode()
    soup = BeautifulSoup(json,"html.parser")
    tag = soup.find(id = 'erb')
    print(tag.string)
def main():
    filename = sys.argv[1]
    haml2html(filename)
    
if __name__ == '__main__':
    main()
