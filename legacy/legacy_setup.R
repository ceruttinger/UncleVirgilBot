
install.packages("pdftools")
install.packages("tesseract")
install.packages("tidyverse")
install.packages("tidytext")

library(pdftools)
library(tesseract)
library(tidyverse)
library(tidytext)



dir_path <- "/Users/clark3/Documents/Virgil/harris/cptrs"

# Get a list of all PDF files in the directory
pdf_files <- list.files(path = dir_path, pattern = "*.pdf", full.names = TRUE)

# Loop through each PDF file
for (pdf_file in pdf_files) {
  # Convert PDF to PNG
  pngfile <- pdftools::pdf_convert(pdf_file, dpi = 600)
  
  # Extract text using OCR
  text <- tesseract::ocr(pngfile)
  
  # Extract the file name without extension
  file_name <- tools::file_path_sans_ext(basename(pdf_file))
  
  # Save the extracted text as an RDS file with the same name as the PDF
  saveRDS(text, file.path(dir_path, paste0(file_name, ".rds")))
}

rds_files <- list.files(path = dir_path, pattern = "*.rds", full.names = TRUE)
# Remove the 12th element
# Remove the 12th element
rds_files <- rds_files[-12]

# Find indices of 'CH-10.rds' and 'CH-11.rds'
# Step 2: Move the 2nd and 3rd elements to positions 10 and 11
# Extract the elements to move
elements_to_move <- rds_files[2:3]

# Remove the elements from their original positions
rds_files <- rds_files[-c(2, 3)]

# Insert the extracted elements at positions 10 and 11
rds_files <- append(rds_files, elements_to_move, after = 9)

# Print the updated list
print(rds_files)
# Read and combine all RDS files into one list
combined_text <- map(rds_files, readRDS)

# Flatten the list into a single character vector (if needed)
combined_text <- unlist(combined_text)

# Save the combined text as a new RDS file
saveRDS(combined_text, file.path(dir_path, "combined_text.rds"))

combined_text <- readRDS("/Users/clark3/Documents/Virgil/harris/cptrs/combined_text.rds")

# Print the contents of the combined text
print(combined_text)

library(tm)
corpus <- iconv(combined_text)
corpus <- Corpus(VectorSource(corpus))
inspect(corpus[1:5])

corpus <- tm_map(corpus, content_transformer(tolower))

corpus <- tm_map(corpus, tolower)
inspect(corpus[1:5])

corpus <- tm_map(corpus, removePunctuation)

corpus <- tm_map(corpus, removeNumbers)

cleanset <- tm_map(corpus, removeWords, stopwords('english'))


#text stemming
cleanset <- tm_map(cleanset, removeWords, c('aapl', 'apple'))  # need to add more words to this after reviewing corpus
cleanset <- tm_map(cleanset, gsub,
                   pattern = 'stocks',
                   replacement = 'stock')
cleanset <- tm_map(cleanset, stemDocument)
cleanset <- tm_map(cleanset, stripWhitespace)

tdm <- TermDocumentMatrix(cleanset)
tdm <- as.matrix(tdm)
tdm[1:10, 1:20]

w <- rowSums(tdm)
w <- subset(w, w>=25)
barplot(w,
        las = 2,
        col = rainbow(50))

library(wordcloud)
w <- sort(rowSums(tdm), decreasing = TRUE)
set.seed(222)
wordcloud(words = names(w),
          freq = w,
          max.words = 20,
          random.order = F,
          min.freq = 5,
          colors = brewer.pal(8, 'Dark2'),
          scale = c(5, 0.3),
          rot.per = 0.7)

library(wordcloud2)
w <- data.frame(names(w), w)
colnames(w) <- c('word', 'freq')
wordcloud2(w,
           size = 0.7,
           shape = 'triangle',
           rotateRatio = 0.5,
           minSize = 1)


library(syuzhet)
library(lubridate)
library(ggplot2)
library(scales)
library(reshape2)
library(dplyr)

words <- iconv(combined_text)
s <- get_nrc_sentiment(words)
head(s)
barplot(colSums(s),
        las = 2,
        col = rainbow(10),
        ylab = 'Count',
        main = "Virgil's Overall Sentiment Scores")

# Define the directory path
dir_path <- "/Users/clark3/Documents/Virgil/harris/cptrs"

# # Get a list of all RDS files in the directory
# rds_files <- list.files(path = dir_path, pattern = "*.rds", full.names = TRUE)
# 
# # Loop through each RDS file
# for (rds_file in rds_files) {
#   # Read the RDS file
#   chapter <- readRDS(rds_file)
#   
#   # Convert the text encoding
#   words <- iconv(chapter, to = "UTF-8")
#   
#   # Perform sentiment analysis
#   s <- get_nrc_sentiment(words)
#   
#   # Extract the file name without extension
#   file_name <- tools::file_path_sans_ext(basename(rds_file))
#   
#   # Define the path to save the plot
#   plot_path <- file.path(dir_path, paste0(file_name, "_sentiment.png"))
#   
#   # Create the bar chart using ggplot2
#   sums <- colSums(s)
#   df <- data.frame(sentiment = names(sums), count = sums)
#   p <- ggplot(df, aes(x = sentiment, y = count, fill = sentiment)) +
#     geom_bar(stat = "identity") +
#     theme_minimal() +
#     labs(
#       title = paste(file_name, "Sentiment Scores"),
#       y = 'Count',
#       x = 'Sentiment'
#     ) +
#     theme(axis.text.x = element_text(angle = 45, hjust = 1))
#   
#   # Save the plot as a PNG file
#   ggsave(plot_path, plot = p, width = 8, height = 6)
# }
# Get a list of all RDS files in the directory
rds_files <- list.files(path = dir_path, pattern = "*.rds", full.names = TRUE)

# Initialize an empty data frame to store all results
s_all <- data.frame()

# First loop: Process each RDS file and store sentiment data
for (rds_file in rds_files) {
  # Read the RDS file
  chapter <- readRDS(rds_file)
  
  # Convert the text encoding
  words <- iconv(chapter, to = "UTF-8")
  
  #make the chapter one single string
  words <- paste(chapter, collapse = " ")
  # Perform sentiment analysis
  s <- get_nrc_sentiment(words)
  
  # Extract the file name without extension
  file_name <- tools::file_path_sans_ext(basename(rds_file))
  
  # Add a file_name column to the results
  s$file_name <- file_name
  
  # Append results to the master dataframe
  s_all <- rbind(s_all, s)
}

# Save the combined sentiment data as an RDS file
saveRDS(s_all, file = file.path(dir_path, "all_sentiments.rds"))

# Second loop: Generate sentiment bar charts for each file
for (file in unique(s_all$file_name)) {
  # Filter data for the current file
  s_subset <- s_all[s_all$file_name == file, ]
  
  # Compute sentiment sums
  sums <- colSums(s_subset[, -ncol(s_subset)])  # Exclude file_name column
  
  # Create a data frame for plotting
  df <- data.frame(sentiment = names(sums), count = sums)
  
  # Define the path to save the plot
  plot_path <- file.path(dir_path, paste0(file, "_sentiment.png"))
  
  # Create the bar chart using ggplot2
  p <- ggplot(df, aes(x = sentiment, y = count, fill = sentiment)) +
    geom_bar(stat = "identity") +
    theme_minimal() +
    labs(
      title = paste(file, "Sentiment Scores"),
      y = 'Count',
      x = 'Sentiment'
    ) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  # Save the plot as a PNG file
  ggsave(plot_path, plot = p, width = 8, height = 6)
}


# Loop through each RDS file
for (rds_file in rds_files) {
  # Read the RDS file
  chapter <- readRDS(rds_file)
  
  # Convert the text encoding
  words <- iconv(chapter, to = "UTF-8")
  
  # Create a corpus
  corpus <- Corpus(VectorSource(words))
  
  # Preprocess the text
  corpus <- tm_map(corpus, content_transformer(tolower))
  corpus <- tm_map(corpus, removePunctuation)
  corpus <- tm_map(corpus, removeNumbers)
  corpus <- tm_map(corpus, removeWords, stopwords("english"))
  
  # Generate the word cloud
  file_name <- tools::file_path_sans_ext(basename(rds_file))
  plot_path <- file.path(dir_path, paste0(file_name, "_wordcloud.png"))
  
  # Save the word cloud as a PNG file
  png(plot_path, width = 800, height = 600)
  # Generate the word cloud (store it in a variable)
  wc <- wordcloud(words = corpus, max.words = 100, random.order = FALSE, colors = brewer.pal(8, "Dark2"), scale = c(2, 0.5)) # Adjust scale as needed
  
  # Plot the word cloud with the title
  plot(wc, main = paste(file_name, "Word Cloud"))
  #wordcloud(words = corpus, max.words = 100, random.order = FALSE, colors = brewer.pal(8, "Dark2"))
  dev.off()
}

library(tm)
library(wordcloud)
library(RColorBrewer)
library(tictoc)  # For timing the operations

# Define the directory path
dir_path <- "/Users/clark3/Documents/Virgil/harris/cptrs"

# Get a list of all RDS files in the directory
rds_files <- list.files(path = dir_path, pattern = "*.rds", full.names = TRUE)

# Start timing the entire process
tic("Total processing time")


# Loop through each RDS file
for (rds_file in rds_files) {
  tryCatch({
    # Time each file processing
    tic(paste("Processing", rds_file))
    
    # Read the RDS file
    chapter <- readRDS(rds_file)
    
    # Convert the text encoding
    words <- iconv(chapter, to = "UTF-8")
    
    # Create a corpus
    corpus <- Corpus(VectorSource(words))
    
    # Preprocess the text
    corpus <- tm_map(corpus, content_transformer(tolower))
    corpus <- tm_map(corpus, removePunctuation)
    corpus <- tm_map(corpus, removeNumbers)
    corpus <- tm_map(corpus, removeWords, stopwords("english"))
    
    # Generate the word cloud
    file_name <- tools::file_path_sans_ext(basename(rds_file))
    title <- paste(file_name, "Word Cloud")  # Create title
    plot_path <- file.path(dir_path, paste0(file_name, "_wordcloud.png"))
    
    # Save the word cloud as a PNG file
    png(plot_path, width = 800, height = 600)
    wordcloud(words = corpus, max.words = 100, random.order = FALSE, colors = brewer.pal(8, "Dark2"), main = title)  # Add title
    dev.off()
    
    # Print success message
    print(paste("Successfully saved:", plot_path))
    
    # End timing for the current file
    toc()
  }, error = function(e) {
    # Print error message
    print(paste("Error processing file:", rds_file, "-", e$message))
  })
}


# End timing the entire process
toc()




########## prep for llm
# Assuming your 'corpus' object is loaded
corpus_texts <- sapply(corpus$content, function(x) paste(x, collapse = " "))

# Create a data frame with the text
corpus_df <- data.frame(text = corpus_texts)

# Save it to a JSON file
library(jsonlite)
write_json(corpus_df, "corpus_data.json")

library(reticulate)
py_config()

use_condaenv("qlora_env", conda = "/usr/local/Caskroom/miniconda/base/condabin/conda")



