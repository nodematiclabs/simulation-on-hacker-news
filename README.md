# Simulation on Hacker News

> An example analytics application which uses AWS Kinesis, AWS Redshift, and Retool

## Conceptual Prerequisites

1. Running Python scripts and managing Python dependencies
1. Working with the AWS Management Console _or_ working with Terraform

## Technical Prerequisites

1. An AWS user, with known Access Key ID and Secret Access Key
    1. The user must have permissions across Kinesis, CloudWatch, S3, and Redshift
1. An account on https://retool.com

## Install

Install Postgresql packages, which will be used to interact with your Redshift cluster.  If using `apt` for package management:
```
sudo apt install postgresql
sudo apt install libpq-dev
```

Install required Python packages
```
python3 -v venv venv
source venv/bin/activate
pip3 install -r data-collector/requirements.txt
```

## Configuration

Setup AWS credential environment variables:
```
export AWS_ACCESS_KEY_ID={{ FILL THIS IN }}
export AWS_SECRET_ACCESS_KEY={{ FILL THIS IN }}
```

## Provisioning

Use terraform to create the data-platform in [the data-platform folder](data-platform).  Use whatever values you'd like for the inputs.
```
cd data-platform
terraform init
terraform apply
cd ..
```
An error will surface for invalid inputs (e.g., insufficient password complexity) - in these cases, run the `terraform apply` again and provide better values.  Note the output values for `endpoint`, `username`, `password`, and `region` after the terraform provisioning completes.

## Collect Data

Change the `INTEREST` value, to something you are interested in which is likely to show up in Hacker News post titles.  _Provide the value in all capitals, like "PYTHON" or "RUST"_ (the search for this value in posts will be case insensitive).

Run the data collection script, with arguments based on the printed terraform output values.
```
# Example values
python3 collect.py --endpoint on-hacker-news.abc123.us-east-1.redshift.amazonaws.com:5439 --username nodematic --password MyPass63? --region us-east-1
```

## Create a Visualization Webpage in Retool

Create a new Retool app, and in that app:
1. Use Amazon Redshift as a resource
    1. Use the endpoint, username, and password from terraform provisioning
    1. Note that the host field should not have the `:5439` port specification
    1. Connect using SSL
1. Create a single query called `on_hacker_news`
    ```
    SELECT   trunc(timestamp 'epoch' + extraction_datetime * interval '1 second') AS extraction_date,
            (in_title_count         + in_url_count)                              AS count,
            compound_sentiment_score, (
            CASE
                    WHEN compound_sentiment_score < -0.6 THEN -2
                    WHEN compound_sentiment_score < -0.2 THEN -1
                    WHEN compound_sentiment_score < 0.2 THEN 0
                    WHEN compound_sentiment_score < 0.6 THEN 1
                    ELSE 2
            END) AS compound_sentiment_index, (
            CASE
                    WHEN compound_sentiment_index = -2 THEN 'Very Negative'
                    WHEN compound_sentiment_index = -1 THEN 'Negative'
                    WHEN compound_sentiment_index = 0 THEN 'Neutral'
                    WHEN compound_sentiment_index = 1 THEN 'Positive'
                    ELSE 'Very Positive'
            END) AS compound_sentiment_category
    FROM     on_hacker_news
    ORDER BY compound_sentiment_index;
    ```
1. Create a Chart (plotly) component, and use [`data-visualization/plotly.json`](data-visualization/plotly.json) for the configuration