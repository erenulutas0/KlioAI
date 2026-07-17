package com.ingilizce.calismaapp.dto;

public class CreateWordRequest {
    
    private String english;
    private String turkish;
    private String addedDate;
    private String difficulty;
    private String notes;
    
    // Constructors
    public CreateWordRequest() {}
    
    public CreateWordRequest(String english, String turkish, String addedDate, String difficulty, String notes) {
        this.english = english;
        this.turkish = turkish;
        this.addedDate = addedDate;
        this.difficulty = difficulty;
        this.notes = notes;
    }
    
    // Getters and Setters
    public String getEnglish() {
        return english;
    }
    
    public void setEnglish(String english) {
        this.english = english;
    }
    
    public String getTurkish() {
        return turkish;
    }
    
    public void setTurkish(String turkish) {
        this.turkish = turkish;
    }

    public String getSourceMeaning() {
        return turkish;
    }

    public void setSourceMeaning(String sourceMeaning) {
        if ((this.turkish == null || this.turkish.isBlank()) && sourceMeaning != null) {
            this.turkish = sourceMeaning;
        }
    }
    
    public String getAddedDate() {
        return addedDate;
    }
    
    public void setAddedDate(String addedDate) {
        this.addedDate = addedDate;
    }
    
    public String getDifficulty() {
        return difficulty;
    }
    
    public void setDifficulty(String difficulty) {
        this.difficulty = difficulty;
    }
    
    public String getNotes() {
        return notes;
    }
    
    public void setNotes(String notes) {
        this.notes = notes;
    }
}
