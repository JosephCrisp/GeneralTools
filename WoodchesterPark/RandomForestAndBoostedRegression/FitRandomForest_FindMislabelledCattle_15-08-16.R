#################
# Load Packages #
#################
suppressMessages(library(randomForest))

#####################################################
# Read in the Genetic Vs. Epidemiological Distances #
#####################################################

# Get the path to the necessary files
path <- "/home/josephcrispell/storage/Research/Woodchester_CattleAndBadgers/NewAnalyses_22-03-18/"

# Read Genetic V.s Epi Distances table
file <- paste(path, "Mislabelling/Cattle-RF-BR/",
              "GeneticVsEpidemiologicalDistances_05-04-18.txt", sep="")
table <- read.table(file, header=TRUE)

# Select only cattle-cattle comparisons
table <- table[table$iSpeciesJSpecies == "CC", ]

# Remove irrelevant columns
table <- removeColumnsIfNotRelevant(table)

# Ignore species column
table <- table[, -which(names(table) == "iSpeciesJSpecies")]

#################################
# Examine the Genetic Distances #
#################################

# Set threshold 
threshold <- 15 # TRYING THIS OUT

par(mfrow=c(3,1))

hist(table$GeneticDistance, 
     las=1,
     xlab="Genetic Distance (SNPs)",
     main="Inter-Isolate Genetic Distance Distribution")

hist(table[table$GeneticDistance < 50, ]$Genetic, 
     las=1,
     xlab="Genetic Distance (SNPs)",
     main="Inter-Isolate Genetic Distance Distribution < 50 SNPs")
lines(x=c(threshold, threshold), y=c(0, 8500), col="red", lty=2)

hist(table[table$GeneticDistance < threshold, ]$Genetic, 
     las=1,
     xlab="Genetic Distance (SNPs)",
     main=paste("Inter-Isolate Genetic Distance Distribution < ",
                threshold, " SNPs", sep=""))

par(mfrow=c(1,1))

#######################################
# Select only Small Genetic Distances #
#######################################

table <- table[table$GeneticDistance < threshold, ]

###########################################################
# Fit the Random Forest Model to test Variation Explained #
###########################################################

# Split the data into train and test sets
trainProp <- 0.5
trainRows <- sample(x=1:nrow(table),
                    size=floor(trainProp * nrow(table)), replace=FALSE)

# Define the columns of the table we're interested in
cols <- 2:(ncol(table)-2)
nTrees <- 1000

# Run the Random Forest tuning algorithm to find the optimal mtry value
tuneOutput <- runRandomForestTuning(table[trainRows, ], 3, nTrees, cols)
plot(tuneOutput, las=1, type="o")

 # Calculate the mtry from the tuning output
mTry <- as.integer(rownames(tuneOutput)[tuneOutput[,2] == min(tuneOutput[,2])])
points(x=mTry, y=tuneOutput[which(tuneOutput[, 1] == mTry), 2], col="red",
       pch=20)

# Run Random Forest Algorithm
nTrees <- 1000
infoRF <- randomForest(table[trainRows, "GeneticDistance"]~., data=table[trainRows, cols],
                       proximity=FALSE, mtry=mTry, importance=TRUE,
                       ntree=nTrees, do.trace=FALSE, keep.forest=TRUE,
                       norm.votes=FALSE)
plot(infoRF, las=1)

# Add the predicted values onto the table
predictions <- predict(infoRF, table[-trainRows, cols])

# Get the Pseudo RSquared value
rSq <- round(infoRF$rsq[length(infoRF$rsq)], digits=2)

###################################################
# Fit the Random Forest Model to find Mislabelled #
###################################################

# Define the columns of the table we're interested in
cols <- 2:(ncol(table)-2)
nTrees <- 1000

# Run the Random Forest tuning algorithm to find the optimal mtry value
tuneOutput <- runRandomForestTuning(table, 3, nTrees, cols)
plot(tuneOutput, las=1, type="o")

# Calculate the mtry from the tuning output
mTry <- as.integer(rownames(tuneOutput)[tuneOutput[,2] == min(tuneOutput[,2])])
points(x=mTry, y=tuneOutput[which(tuneOutput[, 1] == mTry), 2], col="red",
       pch=20)

# Run Random Forest Algorithm
nTrees <- 1000
infoRF <- randomForest(table$GeneticDistance~., data=table[, cols],
                         proximity=FALSE, mtry=mTry, importance=TRUE,
                         ntree=nTrees, do.trace=FALSE, keep.forest=FALSE,
                         norm.votes=FALSE)
plot(infoRF, las=1)

# Add the predicted values onto the table
table$predictions <- infoRF$predicted

# Calculate the mean Difference between the actual and predicted values for each isolate
meanValues <- examinePredictedVersusActual(table)

#################
# Plot the Data #
#################

# Open an output PDF file
file <- paste(path, "Mislabelling/Cattle-RF-BR/",
              "FittedRandomForest_12-07-18.pdf", sep="")
pdf(file)

par(mfrow=c(1,1))

# Plot the forest building output
plot(infoRF, las=1)

# Predicted Versus Actual
smoothScatter(predictions, table[-trainRows, "GeneticDistance"],
              main="Actual vs. Predicted",
              cex.main=1,
              xlab="Predicted",
              ylab="Actual",
              nrpoints=0, las=1)
abline(lm(table$GeneticDistance ~ table$predictions), col="red")
corr <- cor(table[-trainRows, "GeneticDistance"], predictions)
correlation <- round(corr, digits=2)
rSq <- round(corr^2, digits=2)
legend("topleft", legend=c(paste("corr =", correlation), paste("Rsq =", rSq)), bty="n", cex = 1)

# Isolate Prediction
plotMeanValues(meanValues, 2, "Isolate Prediction", 
               "Median Difference",
               cex.main=1, cex.leg=1)

dev.off()

#############################
# Store Isolate Predictions #
#############################

file <- paste(path, "Mislabelling/Cattle-RF-BR/", 
              "MeanValuesTable_RandomForest_12-07-2018.csv", sep="")
write.table(meanValues, file, quote=FALSE, row.names=FALSE, sep=",")

#############
# FUNCTIONS #
#############

  removeColumnsIfNotRelevant <- function(table){
    
    # For particular comparisons: Badger-Badger, Badger-Cattle, Cattle-Cattle
    # some epidemiological metrics aren't relevant and column will be filled 
    # with -1
    
    colsToRemove <- c()
    index <- 0
    
    for(col in 3:(ncol(table)-2)){
      
      if(sd(table[, col]) == 0){
        index <- index + 1
        colsToRemove[index] <- col
        cat(paste("Removed: ", colnames(table)[col], "\n", sep=""))
      }
    }
    return(table[, -colsToRemove])
  }
  
  runRandomForestTuning <- function(inputTable, initialMtry, nTrees, cols){
    
    tuneOutput <- tuneRF(inputTable[, cols], inputTable$Genetic, mtryStart=initialMtry,
                         ntreeTry=nTrees, stepFactor=1.5, improve=0.0001, trace=TRUE,
                         plot=TRUE)
    
    return(tuneOutput)
  }
  
  plotMeanValues <- function(inputTable, column, title, yLabel, cex.main, cex.leg){
    
    ## Plotting the Mean Difference between the predicted and actual genetic distances for 
    #  each isolate
    
    # Input table structure:
    # Mean  Median  Lower Upper Range
    # 1     2       3     4     5    
    
    # Find the Boundary where 95% of data lie below
    bound95<- quantile(inputTable[,column], c(0.95))
    
    # Highlight and Label Outliers
    plot(inputTable[,column],
         ylab=yLabel,
         main=title, cex.main=cex.main,
         pch=20, bty="n", xlab="", xaxt="n", las=1)
    text(x=1:nrow(inputTable), y=inputTable[,column], labels=rownames(inputTable),
         col=ifelse(inputTable[,column] >= bound95, rgb(1,0,0), rgb(0,0,0, 0)), xpd=TRUE)
    abline(h=bound95, col="red")
    legend("topright", paste("Upper = ", round(bound95, digits=3)), bty="n",
           cex=cex.leg)
    
    # A histogram
    hist(inputTable[,column], breaks=20, main="Isolate Prediction", xlab=paste(column, " difference", sep=""))
    
    # Print the outliers
    print(rownames(inputTable)[inputTable[,column] >= bound95])
  }
  
  examinePredictedVersusActual <- function(inputTable){
    
    ## Store a distribution of the difference between the predicted
    ## and actual genetic distances for each isolate
    
    # Input table structure:
    # GeneticDistance iSpeciesJSpecies  EpiMetricA  EpiMetricB  ... IsolateI  IsolateJ  Predicted
    # 0               1                 2           3           ... -2        -1        ncol(table)
    
    # Ensure the Isolate ID columns are vectors of strings
    inputTable$IsolateI <- as.character(inputTable$IsolateI)
    inputTable$IsolateJ <- as.character(inputTable$IsolateJ)
    
    # Initialise a list to store the difference distributions for each isolate
    isolates <- list()
    
    # Examine each row of the input table
    for(row in 1:nrow(inputTable)){
      
      ## Check the I Isolate ID
      # Have we envountered this isolate before?
      if(is.null(isolates[[inputTable[row, ncol(inputTable) - 2]]]) == TRUE){
        
        # Calculate the difference between the predicted and actual values
        difference <- abs(inputTable[row, ncol(inputTable)] - inputTable[row, 1])
        
        # Store the array of calculated differences
        isolates[[inputTable[row, ncol(inputTable) - 2]]] <- c(difference)
        
        # We have encountered this isolate - append the difference
      }else{
        
        # Calculate the difference between the predicted and actual values
        difference <- abs(inputTable[row, ncol(inputTable)] - inputTable[row, 1])
        
        # Append the calculated difference to the array
        isolates[[inputTable[row, ncol(inputTable) - 2]]] <- c(isolates[[inputTable[row, ncol(inputTable) - 2]]], difference)
      }
      
      ## Check the J Isolate ID
      # Have we envountered this isolate before?
      if(is.null(isolates[[inputTable[row, ncol(inputTable) - 1]]]) == TRUE){
        
        # Calculate the difference between the predicted and actual values
        difference <- abs(inputTable[row, ncol(inputTable)] - inputTable[row, 1])
        
        # Store the array of calculated differences
        isolates[[inputTable[row, ncol(inputTable) - 1]]] <- c(difference)
        
        # We have encountered this isolate - append the difference  
      }else{
        
        # Calculate the difference between the predicted and actual values
        difference <- abs(inputTable[row, ncol(inputTable)] - inputTable[row, 1])
        
        # Append the calculated difference to the array
        isolates[[inputTable[row, ncol(inputTable) - 1]]] <- c(isolates[[inputTable[row, ncol(inputTable) - 1]]], difference)
      }
    }
    
    ## Summarise the distributions of differences for each isolate
    
    # Initialise a table to store a summary of the difference distributions for each isolate
    summaryTable <- data.frame(Mean=rep(0, length(isolates)),
                               Median=rep(0, length(isolates)),
                               Lower=rep(0, length(isolates)),
                               Upper=rep(0, length(isolates)),
                               Range=rep(0, length(isolates)),
                               NumberDistances=rep(0, length(isolates)))
    
    # Get a list of the isolate IDs
    ids <- names(isolates)
    rownames(summaryTable) <- ids
    
    # Examine each isolates difference distribution
    for(i in 1:nrow(summaryTable)){
      
      # Get the distribution of differences for the current isolate
      differences <- isolates[[ids[i]]]
      
      # Calculate the quantiles of the distribution
      quantiles <- quantile(differences, c(0.025, 0.975))
      
      # Summarise the difference distribution
      summaryTable[i,"Mean"] <- mean(differences)
      summaryTable[i,"Median"] <- median(differences)
      summaryTable[i,"Lower"] <- quantiles[[1]]
      summaryTable[i,"Upper"] <- quantiles[[2]]
      summaryTable[i,"Range"] <- quantiles[[2]] - quantiles[[1]]
      summaryTable[i,"NumberDistances"] <- length(differences)
    }
    
    return(summaryTable)
  }