import boto3
import getopt
import json
import nltk
import psycopg2
import requests
import sys
import time

from botocore.config import Config
from nltk.sentiment import SentimentIntensityAnalyzer

INTEREST = "SIMULATION"
HEADERS = {'user-agent': f'python-requests/{requests.__version__} Learning AWS Data Pipelines https://github.com/nodematiclabs/simulation-on-hacker-news'}
STREAM = "on-hacker-news"
DB_NAME = "on_hacker_news"

# Get command line arguments
try:
    opts, args = getopt.getopt(sys.argv[1:],"heupr:",["help", "endpoint=","username=","password=","region="])
except getopt.GetoptError:
    print ('collect.py -e <cluster endpoint> -u <cluster username> -p <cluster password> -r <firehose region>')
    sys.exit(2)
if len(opts) == 0:
    print ('collect.py -e <cluster endpoint> -u <cluster username> -p <cluster password> -r <firehose region>')
    sys.exit(3)
for opt, arg in opts:
    if opt in ('-h', "--help"):
        print ('collect.py -e <cluster endpoint> -u <cluster username> -p <cluster password> -r <firehose region>')
        sys.exit()
    elif opt in ("-e", "--endpoint"):
        endpoint = arg
    elif opt in ("-u", "--username"):
        username = arg
    elif opt in ("-p", "--password"):
        password = arg
    elif opt in ("-r", "--region"):
        region = arg

# Setup clients and libraries
nltk.download('vader_lexicon')
sia = SentimentIntensityAnalyzer()
firehose_config = Config(region_name=region)
firehose_client = boto3.client("firehose", config=firehose_config)

# Create the required database table if it doesn't already exist
connection = psycopg2.connect(
    f"dbname='{DB_NAME}' host='{endpoint.split(':')[0]}' port={endpoint.split(':')[-1]} user='{username}' password='{password}'"
)
cursor = connection.cursor()
cursor.execute(f"""
CREATE TABLE IF NOT EXISTS {DB_NAME} (
  extraction_datetime int,
  title varchar(1023),
  in_title_count int2,
  in_url_count int2,
  positive_sentiment_score float4,
  neutral_sentiment_score float4,
  negative_sentiment_score float4,
  compound_sentiment_score float4
);
""")
connection.commit()
cursor.close()
connection.close()

# Add the latest data from Hacker News
for i in range(0, 1):
    topstories = requests.get("https://hacker-news.firebaseio.com/v0/topstories.json").json()
    for topstory in topstories:
        story = requests.get(f"https://hacker-news.firebaseio.com/v0/item/{topstory}.json").json()
        polarity_scores = sia.polarity_scores(story["title"])
        record = {
            "extraction_datetime": int(time.time()),
            "title": story["title"],
            "in_title_count": story["title"].upper().count(INTEREST),
            "in_url_count": story["url"].upper().count(INTEREST) if "url" in story.keys() else 0,
            "positive_sentiment_score": polarity_scores["pos"],
            "neutral_sentiment_score": polarity_scores["neu"],
            "negative_sentiment_score": polarity_scores["neg"],
            "compound_sentiment_score": polarity_scores["compound"]
        }
        firehose_client.put_record(
            DeliveryStreamName=STREAM, Record={"Data": json.dumps(record)},
        )
        time.sleep(1)